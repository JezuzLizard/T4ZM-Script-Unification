#include maps\_utility; 
#include common_scripts\utility;
#include maps\so\zm_common\_zm_utility;


#using_animtree( "generic_human" ); 
init()
{
	level.zombie_move_speed = 1; 
	level.zombie_health = 150; 
	
	level.zombie_eyes_limited = 1;
	level.zombie_eyes_disabled = 1;
	
	if(getdvarint("g_allzombieseyeglow"))
	{
		level.zombie_eyes_limited = 0;
	}
	
	level._zm_spawner_funcs = [];
	level._zm_spawner_funcs[ "add_spawn_funcs_to_zombie_spawners" ] = ::add_spawn_funcs_to_zombie_spawners;
	level._zm_spawner_funcs[ "zombie_head_gib" ] = ::zombie_head_gib;
	level._zm_spawner_funcs[ "zombie_damage" ] = ::zombie_damage;
	level._zm_spawner_funcs[ "zombie_damage_ads" ] = ::zombie_damage_ads;
	level._zm_spawner_funcs[ "is_spawner_targeted_by_blocker" ] = ::is_spawner_targeted_by_blocker;
	level._zm_spawner_funcs[ "zombie_history" ] = ::zombie_history;
}

add_spawn_funcs_to_zombie_spawners()
{
	zombies = getEntArray( "zombie_spawner", "script_noteworthy" ); 
	later_rounds = getentarray("later_round_spawners", "script_noteworthy" );
	
	zombies = array_combine( zombies, later_rounds );

	for( i = 0; i < zombies.size; i++ )
	{
		if( is_spawner_targeted_by_blocker( zombies[i] ) )
		{
			zombies[i].locked_spawner = true;
		}
	}
	
	array_thread(zombies, ::add_spawn_function, ::zombie_spawn_init);
	array_thread(zombies, ::add_spawn_function, ::zombie_rise);
}


#using_animtree( "generic_human" ); 
is_spawner_targeted_by_blocker( ent )
{
	if( IsDefined( ent.targetname ) )
	{
		targeters = GetEntArray( ent.targetname, "target" );

		for( i = 0; i < targeters.size; i++ )
		{
			if( targeters[i].targetname == "zombie_door" || targeters[i].targetname == "zombie_debris" )
			{
				return true;
			}

			result = is_spawner_targeted_by_blocker( targeters[i] );
			if( result )
			{
				return true;
			}
		}
	}

	return false;
}

// set up zombie walk cycles
zombie_spawn_init()
{
	self.targetname = "zombie";
	self.script_noteworthy = undefined;
	self.animname = "zombie"; 		
	self.ignoreall = true; 
	self.allowdeath = true; 			// allows death during animscripted calls
	self.gib_override = true; 		// needed to make sure this guy does gibs
	self.is_zombie = true; 			// needed for melee.gsc in the animscripts
	self.has_legs = true; 			// Sumeet - This tells the zombie that he is allowed to stand anymore or not, gibbing can take 
									// out both legs and then the only allowed stance should be prone.
	self.gibbed = false; 
	self.head_gibbed = false;
	
	// might need this so co-op zombie players cant block zombie pathing
	self PushPlayer( true ); 
//	self.meleeRange = 128; 
//	self.meleeRangeSq = anim.meleeRange * anim.meleeRange; 
	
	animscripts\shared::placeWeaponOn( self.primaryweapon, "none" ); 
	
	// This isn't working, might need an "empty" weapon
	//self animscripts\shared::placeWeaponOn( self.weapon, "none" ); 

	self allowedStances( "stand" ); 
	self.disableArrivals = true; 
	self.disableExits = true; 
	self.grenadeawareness = 0;
	self.badplaceawareness = 0;

	self.ignoreSuppression = true; 	
	self.suppressionThreshold = 1; 
	self.noDodgeMove = true; 
	self.dontShootWhileMoving = true;
	self.pathenemylookahead = 0;

	self.badplaceawareness = 0;
	self.chatInitialized = false; 

	self disable_pain(); 

	self.maxhealth = level.zombie_health; 
	self.health = level.zombie_health; 

	self.dropweapon = false; 
	level thread zombie_death_event( self ); 

	// We need more script/code to get this to work properly
//	self add_to_spectate_list();
	self random_tan(); 
	self set_zombie_run_cycle(); 
	self thread zombie_think(); 
	self thread zombie_gib_on_damage(); 
	self thread zombie_damage_failsafe();

//	self thread zombie_head_gib(); 
	self thread delayed_zombie_eye_glow();	// delayed eye glow for ground crawlers (the eyes floated above the ground before the anim started)
	self.deathFunction = ::zombie_death_animscript;
	self.flame_damage_time = 0;

	self zombie_history( "zombie_spawn_init -> Spawned = " + self.origin );

	self notify( "zombie_init_done" );
}

/*
delayed_zombie_eye_glow:
Fixes problem where zombies that climb out of the ground are warped to their start positions
and their eyes glowed above the ground for a split second before their animation started even
though the zombie model is hidden. and applying this delay to all the zombies doesn't really matter.
*/
delayed_zombie_eye_glow()
{
	wait .5;
	self zombie_eye_glow();
}


zombie_damage_failsafe()
{
	self endon ("death");

	continue_failsafe_damage = false;	
	while (1)
	{
		//should only be for zombie exploits
		wait 0.5;
		
		if (!isdefined(self.enemy))
		{
			continue;
		}
		
		if (self istouching(self.enemy))
		{
			old_org = self.origin;
			if (!continue_failsafe_damage)
			{
				wait 5;
			}
			
			//make sure player doesn't die instantly after getting touched by a zombie.
			if (!isdefined(self.enemy) || self.enemy hasperk("specialty_armorvest"))
			{
				continue;
			}
		
			if (self istouching(self.enemy) 
				&& !self.enemy maps\_laststand::player_is_in_laststand()
				&& isalive(self.enemy))
			{
				if (distancesquared(old_org, self.origin) < (35 * 35) ) 
				{
					setsaveddvar("player_deathInvulnerableTime", 0);
					self.enemy DoDamage( self.enemy.health + 1000, self.enemy.origin, undefined, undefined, "riflebullet" );
					setsaveddvar("player_deathInvulnerableTime", level.startInvulnerableTime);	
				
					continue_failsafe_damage = true;
				}
			}
		}
		else
		{
			continue_failsafe_damage = false;
		}
	}
}

set_zombie_run_cycle()
{
	self set_run_speed();

	death_anims = [];
	death_anims[death_anims.size] = %ch_dazed_a_death;
	death_anims[death_anims.size] = %ch_dazed_b_death;
	death_anims[death_anims.size] = %ch_dazed_c_death;
	death_anims[death_anims.size] = %ch_dazed_d_death;

	self.deathanim = random(death_anims);

	if(level.round_number < 3)
	{
		self.zombie_move_speed = "walk";
	}

	switch(self.zombie_move_speed)
	{
	case "walk":
		var = randomintrange(1, 8);         
		self set_run_anim( "walk" + var );                         
		self.run_combatanim = level.scr_anim["zombie"]["walk" + var];
		break;
	case "run":                                
		var = randomintrange(1, 6);
		self set_run_anim( "run" + var );               
		self.run_combatanim = level.scr_anim["zombie"]["run" + var];
		break;
	case "sprint":                             
		var = randomintrange(1, 4);
		self set_run_anim( "sprint" + var );                       
		self.run_combatanim = level.scr_anim["zombie"]["sprint" + var];
		break;
	}
}

set_run_speed()
{
	rand = randomintrange( level.zombie_move_speed, level.zombie_move_speed + 35 ); 
	
//	self thread print_run_speed( rand );
	if( rand <= 35 )
	{
		self.zombie_move_speed = "walk"; 
	}
	else if( rand <= 70 )
	{
		self.zombie_move_speed = "run"; 
	}
	else
	{	
		self.zombie_move_speed = "sprint"; 
	}
}

// this is the main zombie think thread that starts when they spawn in
zombie_think()
{
	self endon( "death" ); 
	assert( !self enemy_is_dog() );
	
	//node = level.exterior_goals[randomint( level.exterior_goals.size )]; 
	
	//CHRIS_P - test dudes rising from ground 
	if (GetDVarInt("zombie_rise_test") || (isDefined(self.script_string) && self.script_string == "riser" && randomint(100) > 25))
	{
		self.do_rise = 1;
		//self notify("do_rise");
		self waittill("risen");
	}
	else
	{
		self notify("no_rise");
	}
	
	node = undefined;

	desired_nodes = [];
	self.entrance_nodes = [];

	if( IsDefined( self.script_forcegoal ) && self.script_forcegoal )
	{
		desired_origin = get_desired_origin();

		AssertEx( IsDefined( desired_origin ), "Spawner @ " + self.origin + " has a script_forcegoal but did not find a target" );
	
		origin = desired_origin;
			
		node = getclosest( origin, level.exterior_goals ); 	
		self.entrance_nodes[0] = node;

		self zombie_history( "zombie_think -> #1 entrance (script_forcegoal) origin = " + self.entrance_nodes[0].origin );
	}
	// JMA - this is used in swamp to spawn outdoor zombies and immediately rush the player
	else if( (level.script == "nazi_zombie_sumpf" || level.script == "nazi_zombie_bridgetest" || level.script == "nazi_zombie_bridge_test" ||
		 level.script == "nazi_zombie_drawbridge" || level.script == "nazi_zombie_sluicegate" || level.script == "nazi_zombie_pendulum" || level.script == "nazi_zombie_zipline") && 
		 IsDefined( self.script_string ) && (self.script_string == "zombie_chaser" || self.script_string == "riser") )
	{
		self zombie_setup_attack_properties();
		//if the zombie has a target, make them go there first
		if (isDefined(self.target))
		{
			end_at_node = GetNode(self.target, "targetname");
			if (isDefined(end_at_node))
			{
				self setgoalnode (end_at_node);
				self waittill("goal");
			}
		}

		self thread find_flesh();
		return;	
	}
	else
	{
		origin = self.origin;

		desired_origin = get_desired_origin();
		if( IsDefined( desired_origin ) )
		{
			origin = desired_origin;
		}

		// Get the 3 closest nodes
		nodes = get_array_of_closest( origin, level.exterior_goals, undefined, 3 );

		// Figure out the distances between them, if any of them are greater than 256 units compared to the previous, drop it
		max_dist = 500;
		desired_nodes[0] = nodes[0];
		prev_dist = Distance( self.origin, nodes[0].origin );
		for( i = 1; i < nodes.size; i++ )
		{
			dist = Distance( self.origin, nodes[i].origin );
			if( ( dist - prev_dist ) > max_dist )
			{
				break;
			}

			prev_dist = dist;
			desired_nodes[i] = nodes[i];
		}

		node = desired_nodes[0];
		if( desired_nodes.size > 1 )
		{
			node = desired_nodes[RandomInt(desired_nodes.size)];
		}

		self.entrance_nodes = desired_nodes;

		self zombie_history( "zombie_think -> #1 entrance origin = " + node.origin );

		// Incase the guy does not move from spawn, then go to the closest one instead
		self thread zombie_assure_node();
	}

	AssertEx( IsDefined( node ), "Did not find a node!!! [Should not see this!]" );

	level thread draw_line_ent_to_pos( self, node.origin, "goal" );
	
	self.first_node = node;
	
	self thread zombie_goto_entrance( node );
}

get_desired_origin()
{
	if( IsDefined( self.target ) )
	{
		ent = GetEnt( self.target, "targetname" );
		if( !IsDefined( ent ) )
		{
			ent = getstruct( self.target, "targetname" );
		}
	
		if( !IsDefined( ent ) )
		{
			ent = GetNode( self.target, "targetname" );
		}
	
		AssertEx( IsDefined( ent ), "Cannot find the targeted ent/node/struct, \"" + self.target + "\" at " + self.origin );
	
		return ent.origin;
	}

	return undefined;
}

zombie_goto_entrance( node, endon_bad_path )
{
	assert( !self enemy_is_dog() );
	
	self endon( "death" );
	level endon( "intermission" );

	if( IsDefined( endon_bad_path ) && endon_bad_path )
	{
		// If we cannot go to the goal, then end...
		// Used from find_flesh
		self endon( "bad_path" );
	}



	self zombie_history( "zombie_goto_entrance -> start goto entrance " + node.origin );

	self.got_to_entrance = false;
	self.goalradius = 128; 
	self SetGoalPos( node.origin );
	self waittill( "goal" ); 
	self.got_to_entrance = true;

	self zombie_history( "zombie_goto_entrance -> reached goto entrance " + node.origin );

	// Guy should get to goal and tear into building until all barrier chunks are gone
	self tear_into_building();
		
	//REMOVED THIS, WAS CAUSING ISSUES
	if(isDefined(self.first_node.clip))
	{
		//if(!isDefined(self.first_node.clip.disabled) || !self.first_node.clip.disabled)
		//{
		//	self.first_node.clip disable_trigger();
			self.first_node.clip connectpaths();
		//}
	}

	// here is where they zombie would play the traversal into the building( if it's a window )
	// and begin the player seek logic
	self zombie_setup_attack_properties();
	
	//PI CHANGE - force the zombie to go over the traversal near their goal node if desired
	if (isDefined(level.script) && level.script == "nazi_zombie_sumpf")
	{
		if (isDefined(self.target))
		{
			temp_node = GetNode(self.target, "targetname");
			if (isDefined(temp_node) && isDefined(temp_node.target))
			{
				end_at_node = GetNode(temp_node.target, "targetname");
				if (isDefined(end_at_node))
				{
					self setgoalnode (end_at_node);
					self waittill("goal");
				}
			}
		}
	}
	//END PI CHANGE
	
	self thread find_flesh();
}


zombie_assure_node()
{
	self endon( "death" );
	self endon( "goal" );
	level endon( "intermission" );

	start_pos = self.origin;

	for( i = 0; i < self.entrance_nodes.size; i++ )
	{
		if( self zombie_bad_path() )
		{
			self zombie_history( "zombie_assure_node -> assigned assured node = " + self.entrance_nodes[i].origin );

			println( "^1Zombie @ " + self.origin + " did not move for 1 second. Going to next closest node @ " + self.entrance_nodes[i].origin );
			level thread draw_line_ent_to_pos( self, self.entrance_nodes[i].origin, "goal" );
			self.first_node = self.entrance_nodes[i];
			self SetGoalPos( self.entrance_nodes[i].origin );
		}
		else
		{
			return;
		}
	}	
	// CHRISP - must add an additional check, since the 'self.entrance_nodes' array is not dynamically updated to accomodate for entrance points that can be turned on and off
	// only do this if it's the asylum map
	if(level.script == "nazi_zombie_asylum" || level.script == "nazi_zombie_sumpf" || level.script == "nazi_zombie_factory")
	{
		wait(2);
		// Get more nodes and try again
		nodes = get_array_of_closest( self.origin, level.exterior_goals, undefined, 20 );
		self.entrance_nodes = nodes;
		for( i = 0; i < self.entrance_nodes.size; i++ )
		{
			if( self zombie_bad_path() )
			{
				self zombie_history( "zombie_assure_node -> assigned assured node = " + self.entrance_nodes[i].origin );

				println( "^1Zombie @ " + self.origin + " did not move for 1 second. Going to next closest node @ " + self.entrance_nodes[i].origin );
				level thread draw_line_ent_to_pos( self, self.entrance_nodes[i].origin, "goal" );
				self.first_node = self.entrance_nodes[i];
				self SetGoalPos( self.entrance_nodes[i].origin );
			}
			else
			{
				return;
			}
		}
	}		

	self zombie_history( "zombie_assure_node -> failed to find a good entrance point" );
	
	//assertmsg( "^1Zombie @ " + self.origin + " did not find a good entrance point... Please fix pathing or Entity setup" );
	wait(20);
	//iprintln( "^1Zombie @ " + self.origin + " did not find a good entrance point... Please fix pathing or Entity setup" );
	self DoDamage( self.health + 10, self.origin );
}

zombie_bad_path()
{
	self endon( "death" );
	self endon( "goal" );

	self thread zombie_bad_path_notify();
	self thread zombie_bad_path_timeout();

	self.zombie_bad_path = undefined;
	while( !IsDefined( self.zombie_bad_path ) )
	{
		wait( 0.05 );
	}

	self notify( "stop_zombie_bad_path" );

	return self.zombie_bad_path;
}

zombie_bad_path_notify()
{
	self endon( "death" );
	self endon( "stop_zombie_bad_path" );

	self waittill( "bad_path" );
	self.zombie_bad_path = true;
}

zombie_bad_path_timeout()
{
	self endon( "death" );
	self endon( "stop_zombie_bad_path" );

	wait( 2 );
	self.zombie_bad_path = false;
}

// zombies are trying to get at player contained behind barriers, so the barriers
// need to come down
tear_into_building()
{
	//chrisp - added this 
	//checkpass = false;
	
	self endon( "death" ); 

	self zombie_history( "tear_into_building -> start" );

	while( 1 )
	{
		if( IsDefined( self.first_node.script_noteworthy ) )
		{
			if( self.first_node.script_noteworthy == "no_blocker" )
			{
				return;
			}
		}

		if( !IsDefined( self.first_node.target ) )
		{
			return;
		}

		if( all_chunks_destroyed( self.first_node.barrier_chunks ) )
		{
			self zombie_history( "tear_into_building -> all chunks destroyed" );
		}

		// Pick a spot to tear down
		if( !get_attack_spot( self.first_node ) )
		{
			self zombie_history( "tear_into_building -> Could not find an attack spot" );
			wait( 0.5 );
			continue;
		}

		self.goalradius = 4;
		self SetGoalPos( self.attacking_spot, self.first_node.angles );
		self waittill( "orientdone" );

		self zombie_history( "tear_into_building -> Reach position and orientated" );		

		// chrisp - do one final check to make sure that the boards are still torn down
		// this *mostly* prevents the zombies from coming through the windows as you are boarding them up. 
		if( all_chunks_destroyed( self.first_node.barrier_chunks ) )
		{
			self zombie_history( "tear_into_building -> all chunks destroyed" );
			return;
		}

		// Now tear down boards
		while( 1 )
		{
			chunk = get_closest_non_destroyed_chunk( self.origin, self.first_node.barrier_chunks );
	
			if( !IsDefined( chunk ) )
			{
				for( i = 0; i < self.first_node.attack_spots_taken.size; i++ )
				{
					self.first_node.attack_spots_taken[i] = false;
				}
				return; 
			}

			self zombie_history( "tear_into_building -> animating" );

			tear_anim = get_tear_anim(chunk, self);
			chunk.target_by_zombie = true;
			self AnimScripted( "tear_anim", self.origin, self.first_node.angles, tear_anim );
			self zombie_tear_notetracks( "tear_anim", chunk, self.first_node );
			
			//chris - adding new window attack & gesture animations ;)
			if(level.script != "nazi_zombie_prototype")
			{
				attack = self should_attack_player_thru_boards();
				if(isDefined(attack) && !attack && self.has_legs)
				{
					self do_a_taunt();
				}				
			}		
			//chrisp - fix the extra tear anim bug
			if( all_chunks_destroyed( self.first_node.barrier_chunks ) )
			{
				for( i = 0; i < self.first_node.attack_spots_taken.size; i++ )
				{
					self.first_node.attack_spots_taken[i] = false;
				}
				return;
			}	
		}
		self reset_attack_spot();
	}		
}

/*------------------------------------
checks to see if the zombie should 
do a taunt when tearing thru the boards
------------------------------------*/
do_a_taunt()
{
	if( !self.has_legs)
	{
		return false;
	}

	self.old_origin = self.origin;
	if(getdvar("zombie_taunt_freq") == "")
	{
		setdvar("zombie_taunt_freq","5");
	}
	freq = getdvarint("zombie_taunt_freq");
	
	if( freq >= randomint(100) )
	{
		anime = random(level._zombie_board_taunt);
		self animscripted("zombie_taunt",self.origin,self.angles,anime);
		wait(getanimlength(anime));
		self teleport(self.old_origin);
	}
}

/*------------------------------------
checks to see if the players are near
the entrance and tries to attack them 
thru the boards. 50% chance
------------------------------------*/
should_attack_player_thru_boards()
{
	
	//no board attacks if they are crawlers
	if( !self.has_legs)
	{
		return false;
	}
	
	if(getdvar("zombie_reachin_freq") == "")
	{
		setdvar("zombie_reachin_freq","50");
	}
	freq = getdvarint("zombie_reachin_freq");
	
	players = getPlayers();
	attack = false;
	
	for(i=0;i<players.size;i++)
	{
		if(distance2d(self.origin,players[i].origin) <= 72)
		{
			attack = true;
		}
	}	
	if(attack && freq >= randomint(100) )
	{
		//iprintln("checking attack");
		
		//check to see if the guy is left, right, or center 
		self.old_origin = self.origin;
		if(self.attacking_spot_index == 0) //he's in the center
		{
			
		if(randomint(100) > 50)
		{
			
				self animscripted("window_melee",self.origin,self.angles,%ai_zombie_window_attack_arm_l_out);
		}
		else
		{
			self animscripted("window_melee",self.origin,self.angles,%ai_zombie_window_attack_arm_r_out);
		}
		self window_notetracks( "window_melee" );
	



			
		}
		else if(self.attacking_spot_index == 2) //<-- he's to the left
		{
			self animscripted("window_melee",self.origin,self.angles,%ai_zombie_window_attack_arm_r_out);
			self window_notetracks( "window_melee" );
		}
		else if(self.attacking_spot_index == 1) //<-- he's to the right
		{
			self animscripted("window_melee",self.origin,self.angles,%ai_zombie_window_attack_arm_l_out);
			self window_notetracks( "window_melee" );
		}					
	}
	else
	{
		return false;	
	}
}
window_notetracks(msg)
{
	while(1)
	{
		self waittill( msg, notetrack );

		if( notetrack == "end" )
		{
			//self waittill("end");
			self teleport(self.old_origin);

			return;
		}
		if( notetrack == "fire" )
		{
			if(self.ignoreall)
			{
				self.ignoreall = false;
			}
			self melee();
		}
	}
}


crash_into_building()
{
	self endon( "death" ); 

	self zombie_history( "tear_into_building -> start" );

	while( 1 )
	{
		if( IsDefined( self.first_node.script_noteworthy ) )
		{
			if( self.first_node.script_noteworthy == "no_blocker" )
			{
				return;
			}
		}

		if( !IsDefined( self.first_node.target ) )
		{
			return;
		}

		if( all_chunks_destroyed( self.first_node.barrier_chunks ) )
		{
			self zombie_history( "tear_into_building -> all chunks destroyed" );
			return;
		}

		// Pick a spot to tear down
		if( !get_attack_spot( self.first_node ) )
		{
			self zombie_history( "tear_into_building -> Could not find an attack spot" );
			wait( 0.5 );
			continue;
		}

		self.goalradius = 4;
		self SetGoalPos( self.attacking_spot, self.first_node.angles );
		self waittill( "goal" );
		self zombie_history( "tear_into_building -> Reach position and orientated" );

		// Now tear down boards
		while( 1 )
		{
			chunk = get_closest_non_destroyed_chunk( self.origin, self.first_node.barrier_chunks );
	
			if( !IsDefined( chunk ) )
			{
				for( i = 0; i < self.first_node.attack_spots_taken.size; i++ )
				{
					self.first_node.attack_spots_taken[i] = false;
				}
				return; 
			}

			self zombie_history( "tear_into_building -> crash" );

			//tear_anim = get_tear_anim( chunk ); 
			//self AnimScripted( "tear_anim", self.origin, self.first_node.angles, tear_anim );
			//self zombie_tear_notetracks( "tear_anim", chunk, self.first_node );
			PlayFx( level._effect["wood_chunk_destory"], chunk.origin );
			PlayFx( level._effect["wood_chunk_destory"], chunk.origin + ( randomint( 20 ), randomint( 20 ), randomint( 10 ) ) );
			PlayFx( level._effect["wood_chunk_destory"], chunk.origin + ( randomint( 40 ), randomint( 40 ), randomint( 20 ) ) );
	
			level thread maps\so\zm_common\_zm_blockers::remove_chunk( chunk, self.first_node, true );
			
			if( all_chunks_destroyed( self.first_node.barrier_chunks ) )
			{
				EarthQuake( randomfloatrange( 0.5, 0.8 ), 0.5, chunk.origin, 300 ); 
	
				if( IsDefined( self.first_node.clip ) )
				{
					self.first_node.clip ConnectPaths(); 
					wait( 0.05 ); 
					self.first_node.clip disable_trigger(); 
				}
				else
				{
					for( i = 0; i < self.first_node.barrier_chunks.size; i++ )
					{
						self.first_node.barrier_chunks[i] ConnectPaths(); 
					}
				}
			}
			else
			{
				EarthQuake( RandomFloatRange( 0.1, 0.15 ), 0.2, chunk.origin, 200 ); 
			}
					
		}

		self reset_attack_spot();
	}		
}

reset_attack_spot()
{
	if( IsDefined( self.attacking_node ) )
	{
		node = self.attacking_node;
		index = self.attacking_spot_index;
		node.attack_spots_taken[index] = false;

		self.attacking_node = undefined;
		self.attacking_spot_index = undefined;
	}
}

get_attack_spot( node )
{
	index = get_attack_spot_index( node );
	if( !IsDefined( index ) )
	{
		return false;
	}

	self.attacking_node = node;
	self.attacking_spot_index = index;
	node.attack_spots_taken[index] = true;
	self.attacking_spot = node.attack_spots[index];

	return true;
}

get_attack_spot_index( node )
{
	indexes = [];
	for( i = 0; i < node.attack_spots.size; i++ )
	{
		if( !node.attack_spots_taken[i] )
		{
			indexes[indexes.size] = i;
		}
	}

	if( indexes.size == 0 )
	{
		return undefined;
	}

	return indexes[RandomInt( indexes.size )];
}

zombie_tear_notetracks( msg, chunk, node )
{

	self endon("death");

	chunk thread check_for_zombie_death(self);
	while( 1 )
	{
		self waittill( msg, notetrack );

		if( notetrack == "end" )
		{
			return;
		}

		if( notetrack == "board" )
		{
			if( !chunk.destroyed )
			{
				self.lastchunk_destroy_time = getTime();
	
				PlayFx( level._effect["wood_chunk_destory"], chunk.origin );
				PlayFx( level._effect["wood_chunk_destory"], chunk.origin + ( randomint( 20 ), randomint( 20 ), randomint( 10 ) ) );
				PlayFx( level._effect["wood_chunk_destory"], chunk.origin + ( randomint( 40 ), randomint( 40 ), randomint( 20 ) ) );
	
				level thread maps\so\zm_common\_zm_blockers::remove_chunk( chunk, node, true );
				chunk.successfully_destroyed = true;
				chunk notify("destroyed");
			}
		}
	}
}

check_for_zombie_death(zombie)
{
	self endon("destroyed");
	
	wait(2.5);
	self.target_by_zombie = undefined;


}



get_tear_anim( chunk, zombo )
{

	//level._zombie_board_tearing["left"]["one"] = %ai_zombie_boardtear_l_1;
	//level._zombie_board_tearing["left"]["two"] = %ai_zombie_boardtear_l_2;
	//level._zombie_board_tearing["left"]["three"] = %ai_zombie_boardtear_l_3;
	//level._zombie_board_tearing["left"]["four"] = %ai_zombie_boardtear_l_4;
	//level._zombie_board_tearing["left"]["five"] = %ai_zombie_boardtear_l_5;
	//level._zombie_board_tearing["left"]["six"] = %ai_zombie_boardtear_l_6;

	//level._zombie_board_tearing["middle"]["one"] = %ai_zombie_boardtear_m_1;
	//level._zombie_board_tearing["middle"]["two"] = %ai_zombie_boardtear_m_2;
	//level._zombie_board_tearing["middle"]["three"] = %ai_zombie_boardtear_m_3;
	//level._zombie_board_tearing["middle"]["four"] = %ai_zombie_boardtear_m_4;
	//level._zombie_board_tearing["middle"]["five"] = %ai_zombie_boardtear_m_5;
	//level._zombie_board_tearing["middle"]["six"] = %ai_zombie_boardtear_m_6;

	//level._zombie_board_tearing["right"]["one"] = %ai_zombie_boardtear_r_1;
	//level._zombie_board_tearing["right"]["two"] = %ai_zombie_boardtear_r_2;
	//level._zombie_board_tearing["right"]["three"] = %ai_zombie_boardtear_r_3;
	//level._zombie_board_tearing["right"]["four"] = %ai_zombie_boardtear_r_4;
	//level._zombie_board_tearing["right"]["five"] = %ai_zombie_boardtear_r_5;
	//level._zombie_board_tearing["right"]["six"] = %ai_zombie_boardtear_r_6;
	anims = [];
	anims[anims.size] = %ai_zombie_door_tear_left;
	anims[anims.size] = %ai_zombie_door_tear_right;

	tear_anim = anims[RandomInt( anims.size )];

	if( self.has_legs )
	{

		if(isdefined(chunk.script_noteworthy))
		{

			if(zombo.attacking_spot_index == 0)
			{
				if(chunk.script_noteworthy == "1")
				{

					tear_anim = %ai_zombie_boardtear_m_1;

				}
				else if(chunk.script_noteworthy == "2")
				{

					tear_anim = %ai_zombie_boardtear_m_2;
				}
				else if(chunk.script_noteworthy == "3")
				{

					tear_anim = %ai_zombie_boardtear_m_3;
				}
				else if(chunk.script_noteworthy == "4")
				{

					tear_anim = %ai_zombie_boardtear_m_4;
				}
				else if(chunk.script_noteworthy == "5")
				{

					tear_anim = %ai_zombie_boardtear_m_5;
				}
				else if(chunk.script_noteworthy == "6")
				{

					tear_anim = %ai_zombie_boardtear_m_6;
				}

			}
			else if(zombo.attacking_spot_index == 1)
			{
				if(chunk.script_noteworthy == "1")
				{

					tear_anim = %ai_zombie_boardtear_r_1;

				}
				else if(chunk.script_noteworthy == "3")
				{

					tear_anim = %ai_zombie_boardtear_r_3;
				}
				else if(chunk.script_noteworthy == "4")
				{

					tear_anim = %ai_zombie_boardtear_r_4;
				}
				else if(chunk.script_noteworthy == "5")
				{

					tear_anim = %ai_zombie_boardtear_r_5;
				}
				else if(chunk.script_noteworthy == "6")
				{
					tear_anim = %ai_zombie_boardtear_r_6;
				}
				else if(chunk.script_noteworthy == "2")
				{

					tear_anim = %ai_zombie_boardtear_r_2;
				}

			}
			else if(zombo.attacking_spot_index == 2)
			{
				if(chunk.script_noteworthy == "1")
				{

					tear_anim = %ai_zombie_boardtear_l_1;

				}
				else if(chunk.script_noteworthy == "2")
				{

					tear_anim = %ai_zombie_boardtear_l_2;
				}
				else if(chunk.script_noteworthy == "4")
				{

					tear_anim = %ai_zombie_boardtear_l_4;
				}
				else if(chunk.script_noteworthy == "5")
				{

					tear_anim = %ai_zombie_boardtear_l_5;
				}
				else if(chunk.script_noteworthy == "6")
				{
					tear_anim = %ai_zombie_boardtear_l_6;
				}
				else if(chunk.script_noteworthy == "3")
				{

					tear_anim = %ai_zombie_boardtear_l_3;
				}

			}

		}
		else
		{
			z_dist = chunk.origin[2] - self.origin[2];
			if( z_dist > 70 )
			{
				tear_anim = %ai_zombie_door_tear_high;
			}
			else if( z_dist < 40 )
			{
				tear_anim = %ai_zombie_door_tear_low;
			}
			else
			{
				anims = [];
				anims[anims.size] = %ai_zombie_door_tear_left;
				anims[anims.size] = %ai_zombie_door_tear_right;

				tear_anim = anims[RandomInt( anims.size )];
			}
		}

	}
	else
	{
		anims = [];
		anims[anims.size] = %ai_zombie_attack_crawl;
		anims[anims.size] = %ai_zombie_attack_crawl_lunge;

		tear_anim = anims[RandomInt( anims.size )];
	}

	return tear_anim; 
}

zombie_head_gib( attacker )
{
	if ( is_german_build() )
	{
		return;
	}

	if( IsDefined( self.head_gibbed ) && self.head_gibbed )
	{
		return;
	}

	self.head_gibbed = true;
	self zombie_eye_glow_stop();

	size = self GetAttachSize(); 
	for( i = 0; i < size; i++ )
	{
		model = self GetAttachModelName( i ); 
		if( IsSubStr( model, "head" ) )
		{
			// SRS 9/2/2008: wet em up
			self thread headshot_blood_fx();
			if(isdefined(self.hatmodel))
			{
				self detach( self.hatModel, "" ); 
			}

			self play_sound_on_ent( "zombie_head_gib" );
			
			self Detach( model, "", true ); 
			self Attach( "char_ger_honorgd_zomb_behead", "", true ); 
			break; 
		}
	}

	self thread damage_over_time( self.health * 0.2, 1, attacker );
}

damage_over_time( dmg, delay, attacker )
{
	self endon( "death" );

	if( !IsAlive( self ) )
	{
		return;
	}

	if( !IsPlayer( attacker ) )
	{
		attacker = undefined;
	}

	while( 1 )
	{
		wait( delay );

		if( IsDefined( attacker ) )
		{
			self DoDamage( dmg, self.origin, attacker );
		}
		else
		{
			self DoDamage( dmg, self.origin );
		}
	}
}

// SRS 9/2/2008: reordered checks, added ability to gib heads with airburst grenades
head_should_gib( attacker, type, point )
{
	if ( is_german_build() )
	{
		return false;
	}

	if( self.head_gibbed )
	{
		return false;
	}

	// check if the attacker was a player
	if( !IsDefined( attacker ) || !IsPlayer( attacker ) )
	{
		return false; 
	}

	// check the enemy's health
	low_health_percent = ( self.health / self.maxhealth ) * 100; 
	if( low_health_percent > 10 )
	{
		return false; 
	}

	weapon = attacker GetCurrentWeapon(); 


	// SRS 9/2/2008: check for damage type
	//  - most SMGs use pistol bullets
	//  - projectiles = rockets, raygun
	if( type != "MOD_RIFLE_BULLET" && type != "MOD_PISTOL_BULLET" )
	{
		// maybe it's ok, let's see if it's a grenade
		if( type == "MOD_GRENADE" || type == "MOD_GRENADE_SPLASH" )
		{
			if( Distance( point, self GetTagOrigin( "j_head" ) ) > 55 )
			{
				return false;
			}
			else
			{
				// the grenade airburst close to the head so return true
				return true;
			}
		}
		else if( type == "MOD_PROJECTILE" )
		{
			if( Distance( point, self GetTagOrigin( "j_head" ) ) > 10 )
			{
				return false;
			}
			else
			{
				return true;
			}
		}
		// shottys don't give a testable damage type but should still gib heads
		else if( WeaponClass( weapon ) != "spread" )
		{
			return false; 
		}
	}

	// check location now that we've checked for grenade damage (which reports "none" as a location)
	if( !self animscripts\utility::damageLocationIsAny( "head", "helmet", "neck" ) )
	{
		return false; 
	}

	// check weapon - don't want "none", pistol, or flamethrower
	if( weapon == "none"  || WeaponClass( weapon ) == "pistol" || WeaponIsGasWeapon( self.weapon ) )
	{
		return false; 
	}

	return true; 
}

// does blood fx for fun and to mask head gib swaps
headshot_blood_fx()
{
	if( !IsDefined( self ) )
	{
		return;
	}

	if( !is_mature() )
	{
		return;
	}

	fxTag = "j_neck";
	fxOrigin = self GetTagOrigin( fxTag );
	upVec = AnglesToUp( self GetTagAngles( fxTag ) );
	forwardVec = AnglesToForward( self GetTagAngles( fxTag ) );
	
	// main head pop fx
	PlayFX( level._effect["headshot"], fxOrigin, forwardVec, upVec );
	PlayFX( level._effect["headshot_nochunks"], fxOrigin, forwardVec, upVec );
	
	wait( 0.3 );
	if(IsDefined( self ))
	{
		if ( isDefined( level.enemy_killed_by_tesla_gun_func ) && self [[ level.enemy_killed_by_tesla_gun_func ]]() )
		{
			PlayFxOnTag( level._effect["tesla_head_light"], self, fxTag );
		}
		else
		{
			PlayFxOnTag( level._effect["bloodspurt"], self, fxTag );
		}
	}
}

// gib limbs if enough firepower occurs
zombie_gib_on_damage()
{
//	self endon( "death" ); 

	while( 1 )
	{
		self waittill( "damage", amount, attacker, direction_vec, point, type ); 

		if( !IsDefined( self ) )
		{
			return;
		}

		if( !self zombie_should_gib( amount, attacker, type ) )
		{
			continue; 
		}

		if( self head_should_gib( attacker, type, point ) && type != "MOD_BURNED" )
		{
			self zombie_head_gib( attacker );
			if(IsDefined(attacker.headshot_count))
			{
				attacker.headshot_count++;
			}
			else
			{
				attacker.headshot_count = 1;
			}
			//stats tracking
			attacker.stats["headshots"] = attacker.headshot_count;
			attacker.stats["zombie_gibs"]++;
			attacker.pers[ "headshots" ] = attacker.headshot_count;
			attacker.pers[ "zombie_gibs" ]++;

			continue;
		}

		if( !self.gibbed )
		{
			// The head_should_gib() above checks for this, so we should not randomly gib if shot in the head
			if( self animscripts\utility::damageLocationIsAny( "head", "helmet", "neck" ) )
			{
				continue;
			}

			refs = []; 
			switch( self.damageLocation )
			{
				case "torso_upper":
				case "torso_lower":
					// HACK the torso that gets swapped for guts also removes the left arm
					//  so we need to sometimes do another ref
					refs[refs.size] = "guts"; 
					refs[refs.size] = "right_arm";
					break; 
	
				case "right_arm_upper":
				case "right_arm_lower":
				case "right_hand":
					//if( IsDefined( self.left_arm_gibbed ) )
					//	refs[refs.size] = "no_arms"; 
					//else
					refs[refs.size] = "right_arm"; 
	
					//self.right_arm_gibbed = true; 
					break; 
	
				case "left_arm_upper":
				case "left_arm_lower":
				case "left_hand":
					//if( IsDefined( self.right_arm_gibbed ) )
					//	refs[refs.size] = "no_arms"; 
					//else
					refs[refs.size] = "left_arm"; 
	
					//self.left_arm_gibbed = true; 
					break; 
	
				case "right_leg_upper":
				case "right_leg_lower":
				case "right_foot":
					if( self.health <= 0 )
					{
						// Addition "right_leg" refs so that the no_legs happens less and is more rare
						refs[refs.size] = "right_leg";
						refs[refs.size] = "right_leg";
						refs[refs.size] = "right_leg";
						refs[refs.size] = "no_legs"; 
					}
					break; 
	
				case "left_leg_upper":
				case "left_leg_lower":
				case "left_foot":
					if( self.health <= 0 )
					{
						// Addition "left_leg" refs so that the no_legs happens less and is more rare
						refs[refs.size] = "left_leg";
						refs[refs.size] = "left_leg";
						refs[refs.size] = "left_leg";
						refs[refs.size] = "no_legs";
					}
					break; 
			default:
				
				if( self.damageLocation == "none" )
				{
					// SRS 9/7/2008: might be a nade or a projectile
					if( type == "MOD_GRENADE" || type == "MOD_GRENADE_SPLASH" || type == "MOD_PROJECTILE" )
					{
						// ... in which case we have to derive the ref ourselves
						refs = self derive_damage_refs( point );
						break;
					}
				}
				else
				{
					refs[refs.size] = "guts";
					refs[refs.size] = "right_arm"; 
					refs[refs.size] = "left_arm"; 
					refs[refs.size] = "right_leg"; 
					refs[refs.size] = "left_leg"; 
					refs[refs.size] = "no_legs"; 
					break; 
				}
			}

			if( refs.size )
			{
				self.a.gib_ref = animscripts\death::get_random( refs ); 
			
				// Don't stand if a leg is gone
				if( ( self.a.gib_ref == "no_legs" || self.a.gib_ref == "right_leg" || self.a.gib_ref == "left_leg" ) && self.health > 0 )
				{
					self.has_legs = false; 
					self AllowedStances( "crouch" ); 
										
					which_anim = RandomInt( 5 ); 
					if(self.a.gib_ref == "no_legs")
					{
						
						if(randomint(100) < 50)
						{
							self.deathanim = %ai_zombie_crawl_death_v1;
							self set_run_anim( "death3" );
							self.run_combatanim = level.scr_anim["zombie"]["crawl_hand_1"];
							self.crouchRunAnim = level.scr_anim["zombie"]["crawl_hand_1"];
							self.crouchrun_combatanim = level.scr_anim["zombie"]["crawl_hand_1"];
						}
						else
						{
							self.deathanim = %ai_zombie_crawl_death_v1;
							self set_run_anim( "death3" );
							self.run_combatanim = level.scr_anim["zombie"]["crawl_hand_2"];
							self.crouchRunAnim = level.scr_anim["zombie"]["crawl_hand_2"];
							self.crouchrun_combatanim = level.scr_anim["zombie"]["crawl_hand_2"];
						}


					}
					else if( which_anim == 0 ) 
					{
						self.deathanim = %ai_zombie_crawl_death_v1;
						self set_run_anim( "death3" );
						self.run_combatanim = level.scr_anim["zombie"]["crawl1"];
						self.crouchRunAnim = level.scr_anim["zombie"]["crawl1"];
						self.crouchrun_combatanim = level.scr_anim["zombie"]["crawl1"];
					}
					else if( which_anim == 1 ) 
					{
						self.deathanim = %ai_zombie_crawl_death_v2;
						self set_run_anim( "death4" );
						self.run_combatanim = level.scr_anim["zombie"]["crawl2"];
						self.crouchRunAnim = level.scr_anim["zombie"]["crawl2"];
						self.crouchrun_combatanim = level.scr_anim["zombie"]["crawl2"];
					}
					else if( which_anim == 2 ) 
					{
						self.deathanim = %ai_zombie_crawl_death_v1;
						self set_run_anim( "death3" );
						self.run_combatanim = level.scr_anim["zombie"]["crawl3"];
						self.crouchRunAnim = level.scr_anim["zombie"]["crawl3"];
						self.crouchrun_combatanim = level.scr_anim["zombie"]["crawl3"];
					}
					else if( which_anim == 3 ) 
					{
						self.deathanim = %ai_zombie_crawl_death_v2;
						self set_run_anim( "death4" );
						self.run_combatanim = level.scr_anim["zombie"]["crawl4"];
						self.crouchRunAnim = level.scr_anim["zombie"]["crawl4"];
						self.crouchrun_combatanim = level.scr_anim["zombie"]["crawl4"];
					}
					else if( which_anim == 4 ) 
					{
						self.deathanim = %ai_zombie_crawl_death_v1;
						self set_run_anim( "death3" );
						self.run_combatanim = level.scr_anim["zombie"]["crawl5"];
						self.crouchRunAnim = level.scr_anim["zombie"]["crawl5"];
						self.crouchrun_combatanim = level.scr_anim["zombie"]["crawl5"];
					}
										
				}
			}

			if( self.health > 0 )
			{
				// force gibbing if the zombie is still alive
				self thread animscripts\death::do_gib();

				//stat tracking
				attacker.stats["zombie_gibs"]++;
				attacker.pers[ "zombie_gibs" ]++;
			}
		}
	}
}


zombie_should_gib( amount, attacker, type )
{
	if ( is_german_build() )
	{
		return false;
	}

	if( !IsDefined( type ) )
	{
		return false; 
	}

	switch( type )
	{
		case "MOD_UNKNOWN":
		case "MOD_CRUSH": 
		case "MOD_TELEFRAG":
		case "MOD_FALLING": 
		case "MOD_SUICIDE": 
		case "MOD_TRIGGER_HURT":
		case "MOD_BURNED":
		case "MOD_MELEE":		
			return false; 
	}

	if( type == "MOD_PISTOL_BULLET" || type == "MOD_RIFLE_BULLET" )
	{
		if( !IsDefined( attacker ) || !IsPlayer( attacker ) )
		{
			return false; 
		}

		weapon = attacker GetCurrentWeapon(); 

		if( weapon == "none" )
		{
			return false; 
		}

		if( WeaponClass( weapon ) == "pistol" )
		{
			return false; 
		}

		if( WeaponIsGasWeapon( self.weapon ) )
		{
			return false; 
		}
	}

//	println( "**DEBUG amount = ", amount );
//	println( "**DEBUG self.head_gibbed = ", self.head_gibbed );
//	println( "**DEBUG self.health = ", self.health );

	prev_health = amount + self.health;
	if( prev_health <= 0 )
	{
		prev_health = 1;
	}

	damage_percent = ( amount / prev_health ) * 100; 

	if( damage_percent < 10 /*|| damage_percent >= 100*/ )
	{
		return false; 
	}

	return true; 
}

// SRS 9/7/2008: need to derive damage location for types that return location of "none"
derive_damage_refs( point )
{
	if( !IsDefined( level.gib_tags ) )
	{
		init_gib_tags();
	}
	
	closestTag = undefined;
	
	for( i = 0; i < level.gib_tags.size; i++ )
	{
		if( !IsDefined( closestTag ) )
		{
			closestTag = level.gib_tags[i];
		}
		else
		{
			if( DistanceSquared( point, self GetTagOrigin( level.gib_tags[i] ) ) < DistanceSquared( point, self GetTagOrigin( closestTag ) ) )
			{
				closestTag = level.gib_tags[i];
			}
		}
	}
	
	refs = [];
	
	// figure out the refs based on the tag returned
	if( closestTag == "J_SpineLower" || closestTag == "J_SpineUpper" || closestTag == "J_Spine4" )
	{
		// HACK the torso that gets swapped for guts also removes the left arm
		//  so we need to sometimes do another ref
		refs[refs.size] = "guts";
		refs[refs.size] = "right_arm";
	}
	else if( closestTag == "J_Shoulder_LE" || closestTag == "J_Elbow_LE" || closestTag == "J_Wrist_LE" )
	{
		refs[refs.size] = "left_arm";
	}
	else if( closestTag == "J_Shoulder_RI" || closestTag == "J_Elbow_RI" || closestTag == "J_Wrist_RI" )
	{
		refs[refs.size] = "right_arm";
	}
	else if( closestTag == "J_Hip_LE" || closestTag == "J_Knee_LE" || closestTag == "J_Ankle_LE" )
	{
		refs[refs.size] = "left_leg";
		refs[refs.size] = "no_legs";
	}
	else if( closestTag == "J_Hip_RI" || closestTag == "J_Knee_RI" || closestTag == "J_Ankle_RI" )
	{
		refs[refs.size] = "right_leg";
		refs[refs.size] = "no_legs";
	}
	
	ASSERTEX( array_validate( refs ), "get_closest_damage_refs(): couldn't derive refs from closestTag " + closestTag );
	
	return refs;
}

init_gib_tags()
{
	tags = [];
					
	// "guts", "right_arm", "left_arm", "right_leg", "left_leg", "no_legs"
	
	// "guts"
	tags[tags.size] = "J_SpineLower";
	tags[tags.size] = "J_SpineUpper";
	tags[tags.size] = "J_Spine4";
	
	// "left_arm"
	tags[tags.size] = "J_Shoulder_LE";
	tags[tags.size] = "J_Elbow_LE";
	tags[tags.size] = "J_Wrist_LE";
	
	// "right_arm"
	tags[tags.size] = "J_Shoulder_RI";
	tags[tags.size] = "J_Elbow_RI";
	tags[tags.size] = "J_Wrist_RI";
	
	// "left_leg"/"no_legs"
	tags[tags.size] = "J_Hip_LE";
	tags[tags.size] = "J_Knee_LE";
	tags[tags.size] = "J_Ankle_LE";
	
	// "right_leg"/"no_legs"
	tags[tags.size] = "J_Hip_RI";
	tags[tags.size] = "J_Knee_RI";
	tags[tags.size] = "J_Ankle_RI";
	
	level.gib_tags = tags;
}

zombie_death_points( origin, mod, hit_location, player,zombie )
{
	//ChrisP - no points or powerups for killing zombies
	if(IsDefined(zombie.marked_for_death))
	{
		return;
	}
	
	level thread maps\so\zm_common\_zm_powerups::powerup_drop( origin );
		
	if( !IsDefined( player ) || !IsPlayer( player ) )
	{
		return; 
	}

	//TUEY Play VO if you get a Head Shot
	//add this check ( 3/24/09 - Chrisp)
	if(level.script != "nazi_zombie_prototype")
	{
		level thread play_death_vo(hit_location, player,mod,zombie);
	}

	player maps\so\zm_common\_zm_score::player_add_points( "death", mod, hit_location ); 
}
designate_rival_hero(player, hero, rival)
{
	players = getplayers();

//		iprintlnbold("designating_rival");

	playHero = isdefined(players[hero]);
	playRival = isdefined(players[rival]);
	
	if(playHero && playRival)
	{
		if(randomfloatrange(0,1) < .5)
		{
			playRival = false;
		}
		else
		{
			playHero = false;
		}
	}	
	if(playHero)
	{		
		if( distance (player.origin, players[hero].origin) < 400)
		{
			player_responder = "plr_" + hero+"_";
			players[hero] play_headshot_response_hero(player_responder);
		}
	}		
	
	if(playRival)
	{
		if( distance (player.origin, players[rival].origin) < 400)
		{
			player_responder = "plr_" + rival+"_";
			players[rival] play_headshot_response_rival(player_responder);
		}
	}
}
play_death_vo(hit_location, player,mod,zombie)
{
	// CHRISP - adding some modifiers here so that it doens't play 100% of the time 
	// and takes into account the damage type. 
	//	default is 10% chance of saying something
	//iprintlnbold(mod);
	
	//iprintlnbold(player);
	
	if( getdvar("zombie_death_vo_freq") == "" )
	{
		setdvar("zombie_death_vo_freq","100"); //TUEY moved to 50---We can take this out\tweak this later.
	}
	
	chance = getdvarint("zombie_death_vo_freq");
	
	weapon = player GetCurrentWeapon();
	//iprintlnbold (weapon);
	
	sound = undefined;
	//just return and don't play a sound if the chance is not there
	if(chance < randomint(100) )
	{
		return;
	}

	//TUEY - this funciton allows you to play a voice over when you kill a zombie and its last hit spot was something specific (like Headshot).
	//players = getplayers();
	index = maps\so\zm_common\_zm_weapons::get_player_index(player);
	
	players = getplayers();

	if(!isdefined (level.player_is_speaking))
	{
		level.player_is_speaking = 0;
	}
	if(!isdefined(level.zombie_vars["zombie_insta_kill"] ))
	{
		level.zombie_vars["zombie_insta_kill"] = 0;
	}
	if(hit_location == "head" && level.zombie_vars["zombie_insta_kill"] != 1   )
	{
		//no VO for non bullet headshot kills
		if( mod != "MOD_PISTOL_BULLET" &&	mod != "MOD_RIFLE_BULLET" )
		{
			return;
		}					
		//chrisp - far headshot sounds
		if(distance(player.origin,zombie.origin) > 450)
		{
			//sound = "plr_" + index + "_vox_kill_headdist" + "_" + randomintrange(0, 11);
			plr = "plr_" + index + "_";
			player thread play_headshot_dialog (plr);

			if(index == 0)
			{	//DEMPSEY gets a headshot, response hero Tenko, rival The Doc
			
				designate_rival_hero(player,2,3);	
			}
			if(index == 1)	
			{		
				//Nickolai gets a headshot, response hero Dempsey, rival Tenko
				designate_rival_hero(player,3,2);
			}		
			if(index == 2)
			{
				//Tenko gets a headshot, response hero The Doctor, rival Nickolai
				designate_rival_hero(player,0,1);	
			}
			if(index == 3)
			{
				//The Doc gets a headshot, response hero Nickolai, rival Dempsey
				designate_rival_hero(player,1,0);	
			}
			return;

		}	
		//remove headshot sounds for instakill
		if (level.zombie_vars["zombie_insta_kill"] != 0)
		{			
			sound = undefined;
		}

	}
	if(weapon == "ray_gun")
	{
		//Ray Gun Kills
		if(distance(player.origin,zombie.origin) > 348 && level.zombie_vars["zombie_insta_kill"] == 0)
		{
			rand = randomintrange(0, 100);
			if(rand < 28)
			{
				plr = "plr_" + index + "_";
				player play_raygun_dialog(plr);
				
			}
			
		}	
		return;
	}
	if(weapon == "ray_gun")
	{
		//Ray Gun Kills
		if(distance(player.origin,zombie.origin) > 348 && level.zombie_vars["zombie_insta_kill"] == 0)
		{
			rand = randomintrange(0, 100);
			if(rand < 28)
			{
				plr = "plr_" + index + "_";
				player play_raygun_dialog(plr);
				
			}
			
		}	
		return;
	}
	if( mod == "MOD_BURNED" )
	{
		//TUEY play flamethrower death sounds
		
		//	iprintlnbold(mod);
		plr = "plr_" + index + "_";
		player play_flamethrower_dialog (plr);
		return;
	}	
	//check for close range kills, and play a special sound, unless instakill is on 
	if(distance(player.origin,zombie.origin) < 64 && level.zombie_vars["zombie_insta_kill"] == 0 && mod != "MOD_BURNED")
	{
		//sound = "plr_" + index + "_vox_close" + "_" + randomintrange(0, 6);
		rand = randomintrange(0, 100);
		if(rand < 40)
		{
			plr = "plr_" + index + "_";
			player play_closekill_dialog (plr);				

		}	
		return;
	
	}	
	
	//special case for close range melee attacks while insta-kill is on
	if (level.zombie_vars["zombie_insta_kill"] != 0)
	{
		if( mod == "MOD_MELEE" || mod == "MOD_BAYONET" || mod == "MOD_UNKNOWN" && distance(player.origin,zombie.origin) < 64)
		{
			plr = "plr_" + index + "_";
			player play_insta_melee_dialog(plr);
			//sound = "plr_" + index + "_vox_melee_insta" + "_" + randomintrange(0, 5); 
			return;
		}
		
	}
	if( mod == "MOD_PROJECTILE")
	{	
		//Plays explosion dialog
		plr = "plr_" + index + "_";
		player play_explosion_dialog(plr);

	}
	//Explosive Kills
	if((mod == "MOD_GRENADE_SPLASH" || mod == "MOD_GRENADE") && level.zombie_vars["zombie_insta_kill"] == 0 )
	{
		//Plays explosion dialog
		plr = "plr_" + index + "_";
		player play_explosion_dialog(plr);
		return;

	}

	
/*
	//This keeps multiple voice overs from playing on the same player (both killstreaks and headshots).
	if (level.player_is_speaking != 1 && isDefined(sound) && level.zombie_vars["zombie_insta_kill"] != 0)
	{	
		level.player_is_speaking = 1;
		player playsound(sound, "sound_done");			
		player waittill("sound_done");
		//This ensures that there is at least 2 seconds waittime before playing another VO.
		wait(2);		
		level.player_is_speaking = 0;
	}
	//This allows us to play VO's faster if the player is in Instakill and killing at a short distance.
	else if (level.player_is_speaking != 1 && isDefined(sound) && level.zombie_vars["zombie_insta_kill"] == 0)
	{
		level.player_is_speaking = 1;
		player playsound(sound, "sound_done");			
		player waittill("sound_done");
		//This ensures that there is at least 3 seconds waittime before playing another VO.
		wait(0.5);		
		level.player_is_speaking = 0;

	}	
*/
}
play_headshot_response_hero(player_index)
{
		
		waittime = 0;
		if(!IsDefined( self.one_at_a_time_hero))
		{
			self.one_at_a_time_hero = 0;
		}
		if(!IsDefined (self.vox_resp_hr_headdist))
		{
			num_variants = maps\so\zm_common\_zm_audio::get_number_variants(player_index + "vox_resp_hr_headdist");
		//	iprintlnbold(num_variants);
			self.vox_resp_hr_headdist = [];
			for(i=0;i<num_variants;i++)
			{
				self.vox_resp_hr_headdist[self.vox_resp_hr_headdist.size] = "vox_resp_hr_headdist_" + i;	
			}
			self.vox_resp_hr_headdist_available = self.vox_resp_hr_headdist;
		}
		if(self.one_at_a_time_hero == 0)
		{
			self.one_at_a_time_hero = 1;
			sound_to_play = random(self.vox_resp_hr_headdist_available);
		//	iprintlnbold(player_index + "_" + sound_to_play);
		
			wait(2);
			self maps\so\zm_common\_zm_audio::do_player_playdialog(player_index, sound_to_play, waittime);
			self.vox_resp_hr_headdist_available = array_remove(self.vox_resp_hr_headdist_available,sound_to_play);			
			if (self.vox_resp_hr_headdist_available.size < 1 )
			{
				self.vox_resp_hr_headdist_available = self.vox_resp_hr_headdist;
			}
			self.one_at_a_time_hero = 0;
		}
}
play_headshot_response_rival(player_index)
{
		
		waittime = 0;
		if(!IsDefined( self.one_at_a_time_rival))
		{
			self.one_at_a_time_rival = 0;
		}
		if(!IsDefined (self.vox_resp_riv_headdist))
		{
			num_variants = maps\so\zm_common\_zm_audio::get_number_variants(player_index + "vox_resp_riv_headdist");
			self.vox_resp_riv_headdist = [];
			for(i=0;i<num_variants;i++)
			{
				self.vox_resp_riv_headdist[self.vox_resp_riv_headdist.size] = "vox_resp_riv_headdist_" + i;	
			}
			self.vox_resp_riv_headdist_available = self.vox_resp_riv_headdist;
		}
		if(self.one_at_a_time_rival == 0)
		{
			self.one_at_a_time_rival = 1;
			sound_to_play = random(self.vox_resp_riv_headdist_available);
		//	iprintlnbold(player_index + "_" + sound_to_play);
			self.vox_resp_riv_headdist_available = array_remove(self.vox_resp_riv_headdist_available,sound_to_play);	
			wait(2);		
			self maps\so\zm_common\_zm_audio::do_player_playdialog(player_index, sound_to_play, waittime);
			if (self.vox_resp_riv_headdist_available.size < 1 )
			{
				self.vox_resp_riv_headdist_available = self.vox_resp_riv_headdist;
			}
			self.one_at_a_time_rival = 0;
		}
}
play_projectile_dialog(player_index)
{
		
		waittime = 1;
		if(!IsDefined( self.one_at_a_time))
		{
			self.one_at_a_time = 0;
		}
		if(!IsDefined (self.vox_kill_explo))
		{
			num_variants = maps\so\zm_common\_zm_audio::get_number_variants(player_index + "vox_kill_explo");
			self.vox_kill_explo = [];
			for(i=0;i<num_variants;i++)
			{
				self.vox_kill_explo[self.vox_kill_explo.size] = "vox_kill_explo_" + i;	
			}
			self.vox_kill_explo_available = self.vox_kill_explo;
		}
		if(self.one_at_a_time == 0)
		{
			self.one_at_a_time = 1;
			sound_to_play = random(self.vox_kill_explo_available);
	//		iprintlnbold(player_index + "_" + sound_to_play);
			self.vox_kill_explo_available = array_remove(self.vox_kill_explo_available,sound_to_play);			
			self maps\so\zm_common\_zm_audio::do_player_playdialog(player_index, sound_to_play, waittime);
			if (self.vox_kill_explo_available.size < 1 )
			{
				self.vox_kill_explo_available = self.vox_kill_explo;
			}
			self.one_at_a_time = 0;
		}
}
play_explosion_dialog(player_index)
{
		
		waittime = 0.25;
		if(!IsDefined( self.one_at_a_time))
		{
			self.one_at_a_time = 0;
		}
		if(!IsDefined (self.vox_kill_explo))
		{
			num_variants = maps\so\zm_common\_zm_audio::get_number_variants(player_index + "vox_kill_explo");
			self.vox_kill_explo = [];
			for(i=0;i<num_variants;i++)
			{
				self.vox_kill_explo[self.vox_kill_explo.size] = "vox_kill_explo_" + i;	
			}
			self.vox_kill_explo_available = self.vox_kill_explo;
		}
		if(self.one_at_a_time == 0)
		{
			self.one_at_a_time = 1;
			sound_to_play = random(self.vox_kill_explo_available);
//			iprintlnbold(player_index + "_" + sound_to_play);
			self.vox_kill_explo_available = array_remove(self.vox_kill_explo_available,sound_to_play);			
			self maps\so\zm_common\_zm_audio::do_player_playdialog(player_index, sound_to_play, waittime);
			if (self.vox_kill_explo_available.size < 1 )
			{
				self.vox_kill_explo_available = self.vox_kill_explo;
			}
			self.one_at_a_time = 0;
		}
}
play_flamethrower_dialog(player_index)
{
		
		waittime = 0.5;
		if(!IsDefined( self.one_at_a_time))
		{
			self.one_at_a_time = 0;
		}
		if(!IsDefined (self.vox_kill_flame))
		{
			num_variants = maps\so\zm_common\_zm_audio::get_number_variants(player_index + "vox_kill_flame");
			self.vox_kill_flame = [];
			for(i=0;i<num_variants;i++)
			{
				self.vox_kill_flame[self.vox_kill_flame.size] = "vox_kill_flame_" + i;	
			}
			self.vox_kill_flame_available = self.vox_kill_flame;
		}
		if(self.one_at_a_time == 0)
		{
			self.one_at_a_time = 1;
			sound_to_play = random(self.vox_kill_flame_available);
			self.vox_kill_flame_available = array_remove(self.vox_kill_flame_available,sound_to_play);			

			self maps\so\zm_common\_zm_audio::do_player_playdialog(player_index, sound_to_play, waittime);
			if (self.vox_kill_flame_available.size < 1 )
			{
				self.vox_kill_flame_available = self.vox_kill_flame;
			}
			self.one_at_a_time = 0;
		}
}
play_closekill_dialog(player_index)
{

		waittime = 1;
		if(!IsDefined( self.one_at_a_time))
		{
			self.one_at_a_time = 0;
		}
		if(!IsDefined (self.vox_close))
		{
			num_variants = maps\so\zm_common\_zm_audio::get_number_variants(player_index + "vox_close");
			self.vox_close = [];
			for(i=0;i<num_variants;i++)
			{
				self.vox_close[self.vox_close.size] = "vox_close_" + i;	
			}
			self.vox_close_available = self.vox_close;
		}
		if(self.one_at_a_time == 0)
		{
			self.one_at_a_time = 1;
			if (self.vox_close_available.size >= 1)
			{
				sound_to_play = random(self.vox_close_available);
				self.vox_close_available = array_remove(self.vox_close_available,sound_to_play);
				self maps\so\zm_common\_zm_audio::do_player_playdialog(player_index, sound_to_play, waittime);
			}

			if (self.vox_close_available.size < 1 )
			{
				self.vox_close_available = self.vox_close;
			}
			self.one_at_a_time = 0;
		}
}

play_headshot_dialog(player_index)
{
		
		waittime = 0.25;
		if(!IsDefined (self.vox_kill_headdist))
		{
			num_variants = maps\so\zm_common\_zm_audio::get_number_variants(player_index + "vox_kill_headdist");
			//iprintlnbold(num_variants);
			self.vox_kill_headdist = [];
			for(i=0;i<num_variants;i++)
			{
				self.vox_kill_headdist[self.vox_kill_headdist.size] = "vox_kill_headdist_" + i;
				//iprintlnbold("vox_kill_headdist_" + i);	
			}
			self.vox_kill_headdist_available = self.vox_kill_headdist;
		}
		sound_to_play = random(self.vox_kill_headdist_available);
		//iprintlnbold("LINE:" + player_index + sound_to_play);
		self maps\so\zm_common\_zm_audio::do_player_playdialog(player_index, sound_to_play, waittime);
		self.vox_kill_headdist_available = array_remove(self.vox_kill_headdist_available,sound_to_play);
	
		if (self.vox_kill_headdist_available.size < 1 )
		{
			self.vox_kill_headdist_available = self.vox_kill_headdist;
		}

}
play_tesla_dialog(player_index)
{
		
		waittime = 0.25;
		if(!IsDefined (self.vox_kill_tesla))
		{
			num_variants = maps\so\zm_common\_zm_audio::get_number_variants(player_index + "vox_kill_tesla");
			//iprintlnbold(num_variants);
			self.vox_kill_tesla = [];
			for(i=0;i<num_variants;i++)
			{
				self.vox_kill_tesla[self.vox_kill_tesla.size] = "vox_kill_tesla_" + i;
				//iprintlnbold("vox_kill_tesla_" + i);	
			}
			self.vox_kill_tesla_available = self.vox_kill_tesla;
		}

		if(!isdefined (level.player_is_speaking))
		{
			level.player_is_speaking = 0;
		}

		sound_to_play = random(self.vox_kill_tesla_available);
		//iprintlnbold("LINE:" + player_index + sound_to_play);
		self maps\so\zm_common\_zm_audio::do_player_playdialog(player_index, sound_to_play, waittime);
		self.vox_kill_tesla_available = array_remove(self.vox_kill_tesla_available,sound_to_play);
	
		if (self.vox_kill_tesla_available.size < 1 )
		{
			self.vox_kill_tesla_available = self.vox_kill_tesla;
		}

}
play_raygun_dialog(player_index)
{
		
		waittime = 0.05;
		if(!IsDefined (self.vox_kill_ray))
		{
			num_variants = maps\so\zm_common\_zm_audio::get_number_variants(player_index + "vox_kill_ray");
			//iprintlnbold(num_variants);
			self.vox_kill_ray = [];
			for(i=0;i<num_variants;i++)
			{
				self.vox_kill_ray[self.vox_kill_ray.size] = "vox_kill_ray_" + i;
				//iprintlnbold("vox_kill_ray_" + i);	
			}
			self.vox_kill_ray_available = self.vox_kill_ray;
		}

		if(!isdefined (level.player_is_speaking))
		{
			level.player_is_speaking = 0;
		}

		sound_to_play = random(self.vox_kill_ray_available);
	//	iprintlnbold("LINE:" + player_index + sound_to_play);
		self maps\so\zm_common\_zm_audio::do_player_playdialog(player_index, sound_to_play, waittime);
		self.vox_kill_ray_available = array_remove(self.vox_kill_ray_available,sound_to_play);
	
		if (self.vox_kill_ray_available.size < 1 )
		{
			self.vox_kill_ray_available = self.vox_kill_ray;
		}

}
play_insta_melee_dialog(player_index)
{
		
		waittime = 0.25;
		if(!IsDefined( self.one_at_a_time))
		{
			self.one_at_a_time = 0;
		}
		if(!IsDefined (self.vox_insta_melee))
		{
			num_variants = maps\so\zm_common\_zm_audio::get_number_variants(player_index + "vox_insta_melee");
			self.vox_insta_melee = [];
			for(i=0;i<num_variants;i++)
			{
				self.vox_insta_melee[self.vox_insta_melee.size] = "vox_insta_melee_" + i;	
			}
			self.vox_insta_melee_available = self.vox_insta_melee;
		}
		if(self.one_at_a_time == 0)
		{
			self.one_at_a_time = 1;
			sound_to_play = random(self.vox_insta_melee_available);
			self.vox_insta_melee_available = array_remove(self.vox_insta_melee_available,sound_to_play);
			if (self.vox_insta_melee_available.size < 1 )
			{
				self.vox_insta_melee_available = self.vox_insta_melee;
			}
			self maps\so\zm_common\_zm_audio::do_player_playdialog(player_index, sound_to_play, waittime);
			//self playsound(player_index + sound_to_play, "sound_done" + sound_to_play);			
			//self waittill("sound_done" + sound_to_play);
			wait(waittime);
			self.one_at_a_time = 0;

		}
		//This ensures that there is at least 3 seconds waittime before playing another VO.

}

// Called from animscripts\death.gsc
zombie_death_animscript()
{
	self reset_attack_spot();

	if( isDefined( level.tesla_gun_funcs ) && isDefined( level.tesla_gun_funcs[ "enemy_killed_by_tesla" ] ) && self [[ level.tesla_gun_funcs[ "enemy_killed_by_tesla" ] ]]() )
	{
		return false;
	}

	// If no_legs, then use the AI no-legs death
	if( self.has_legs && IsDefined( self.a.gib_ref ) && self.a.gib_ref == "no_legs" )
	{
		self.deathanim = %ai_gib_bothlegs_gib;
	}

	self.grenadeAmmo = 0;

	// Give attacker points
	
	//ChrisP - 12/8/08 - added additional 'self' argument
	level zombie_death_points( self.origin, self.damagemod, self.damagelocation, self.attacker,self );

	if( self.damagemod == "MOD_BURNED" )
	{
		self thread animscripts\death::flame_death_fx();
	}

	return false;
}

damage_on_fire( player )
{
	self endon ("death");
	self endon ("stop_flame_damage");
	wait( 2 );
	
	while( isdefined( self.is_on_fire) && self.is_on_fire )
	{
		if( level.round_number < 6 )
		{
			dmg = level.zombie_health * RandomFloatRange( 0.2, 0.3 ); // 20% - 30%
		}
		else if( level.round_number < 9 )
		{
			dmg = level.zombie_health * RandomFloatRange( 0.15, 0.25 );
		}
		else if( level.round_number < 11 )
		{
			dmg = level.zombie_health * RandomFloatRange( 0.1, 0.2 );
		}
		else
		{
			dmg = level.zombie_health * RandomFloatRange( 0.1, 0.15 );
		}

		if ( Isdefined( player ) && Isalive( player ) )
		{
			self DoDamage( dmg, self.origin, player );
		}
		else
		{
			self DoDamage( dmg, self.origin, level );
		}
		
		wait( randomfloatrange( 1.0, 3.0 ) );
	}
}

zombie_damage( mod, hit_location, hit_origin, player )
{
	if( is_magic_bullet_shield_enabled( self ) )
	{
		return;
	}

	//ChrisP - 12/8 - no points for killing gassed zombies!
	player.use_weapon_type = mod;
	if(isDefined(self.marked_for_death))
	{
		return;
	}	

	if( !IsDefined( player ) )
	{
		return; 
	}

	if( self zombie_flame_damage( mod, player ) )
	{
		if( self zombie_give_flame_damage_points() )
		{
			player maps\so\zm_common\_zm_score::player_add_points( "damage", mod, hit_location, self enemy_is_dog() );
		}
	}
	else if( isDefined( level.tesla_gun_funcs ) && isDefined( level.tesla_gun_funcs[ "is_tesla_damage" ] ) && self [[ level.tesla_gun_funcs[ "is_tesla_damage" ] ]]( mod ) )
	{
		self [[ level.tesla_gun_funcs[ "tesla_damage_init" ] ]]( hit_location, hit_origin, player );
		return;
	}
	else
	{
		player maps\so\zm_common\_zm_score::player_add_points( "damage", mod, hit_location, self enemy_is_dog() );
	}

	if ( mod == "MOD_GRENADE" || mod == "MOD_GRENADE_SPLASH" )
	{
		if ( isdefined( player ) && isalive( player ) )
		{
			self DoDamage( level.round_number + randomint( 100, 500 ), self.origin, player);
		}
		else
		{
			self DoDamage( level.round_number + randomint( 100, 500 ), self.origin, undefined );
		}
	}
	else if( mod == "MOD_PROJECTILE" || mod == "MOD_EXPLOSIVE" || mod == "MOD_PROJECTILE_SPLASH" || mod == "MOD_PROJECTILE_SPLASH")
	{
		if ( isdefined( player ) && isalive( player ) )
		{
			self DoDamage( level.round_number * randomintrange( 0, 100 ), self.origin, player);
		}
		else
		{
			self DoDamage( level.round_number * randomintrange( 0, 100 ), self.origin, undefined );
		}
	}
	else if( mod == "MOD_ZOMBIE_BETTY" )
	{
		if ( isdefined( player ) && isalive( player ) )
		{
			self DoDamage( level.round_number * randomintrange( 100, 200 ), self.origin, player);
		}
		else
		{
			self DoDamage( level.round_number * randomintrange( 100, 200 ), self.origin, undefined );
		}
	}
	
	
	self thread maps\so\zm_common\_zm_powerups::check_for_instakill( player );
}

zombie_damage_ads( mod, hit_location, hit_origin, player )
{
	if( is_magic_bullet_shield_enabled( self ) )
	{
		return;
	}

	player.use_weapon_type = mod;
	if( !IsDefined( player ) )
	{
		return; 
	}

	if( self zombie_flame_damage( mod, player ) )
	{
		if( self zombie_give_flame_damage_points() )
		{
			player maps\so\zm_common\_zm_score::player_add_points( "damage_ads", mod, hit_location );
		}
	}
	else if( isDefined( level.tesla_gun_funcs ) && isDefined( level.tesla_gun_funcs[ "is_tesla_damage" ] ) && self [[ level.tesla_gun_funcs[ "is_tesla_damage" ] ]]( mod ) )
	{
		self [[ level.tesla_gun_funcs[ "tesla_damage_init" ] ]]( hit_location, hit_origin, player );
		return;
	}
	else
	{
		player maps\so\zm_common\_zm_score::player_add_points( "damage_ads", mod, hit_location );
	}

	self thread maps\so\zm_common\_zm_powerups::check_for_instakill( player );
}

zombie_give_flame_damage_points()
{
	if( GetTime() > self.flame_damage_time )
	{
		self.flame_damage_time = GetTime() + level.zombie_vars["zombie_flame_dmg_point_delay"];
		return true;
	}

	return false;
}

zombie_flame_damage( mod, player )
{
	if( mod == "MOD_BURNED" )
	{
		self.moveplaybackrate = 0.8;
		
		if( !IsDefined( self.is_on_fire ) || ( Isdefined( self.is_on_fire ) && !self.is_on_fire ) )
		{
			self thread damage_on_fire( player );
		}

		do_flame_death = true;
		dist = 100 * 100;
		ai = GetAiArray( "axis" );
		for( i = 0; i < ai.size; i++ )
		{
			if( IsDefined( ai[i].is_on_fire ) && ai[i].is_on_fire )
			{
				if( DistanceSquared( ai[i].origin, self.origin ) < dist )
				{
					do_flame_death = false;
					break;
				}
			}
		}

		if( do_flame_death )
		{
			self thread animscripts\death::flame_death_fx();
		}

		return true;
	}

	return false;
}


zombie_death_event( zombie )
{
	zombie waittill( "death" );
	zombie thread zombie_eye_glow_stop();
	playsoundatposition ("death_vocals", zombie.origin);
	// this is controlling killstreak voice over in the asylum.gsc
	if(isdefined (zombie.attacker) && isplayer(zombie.attacker) && level.script != "nazi_zombie_prototype")
	{
		if(!isdefined ( zombie.attacker.killcounter))
		{
			zombie.attacker.killcounter = 1;
		}
		else
		{
			zombie.attacker.killcounter ++;
		}
		
		if ( IsDefined( zombie.sound_damage_player ) && zombie.sound_damage_player == zombie.attacker )
		{
			
			zombie.attacker thread play_closeDamage_dialog();	
		}

		zombie.attacker notify("zom_kill");
	}
	
}
play_closeDamage_dialog()
{
	index = maps\so\zm_common\_zm_weapons::get_player_index(self);
	player_index = "plr_" + index + "_";
	
	if(!IsDefined (self.vox_dmg_close))
	{
		num_variants = maps\so\zm_common\_zm_audio::get_number_variants(player_index + "vox_dmg_close");
		self.vox_dmg_close = [];
		for(i=0;i<num_variants;i++)
		{
			self.vox_dmg_close[self.vox_dmg_close.size] = "vox_dmg_close_" + i;	
		}
		self.vox_dmg_close_available = self.vox_dmg_close;
	}
	sound_to_play = random(self.vox_dmg_close_available);
	self.vox_dmg_close_available = array_remove(self.vox_dmg_close_available,sound_to_play);
	
	if( self.vox_dmg_close_available.size < 1)
	{
		self.vox_dmg_close_available = self.vox_dmg_close;	
	}
	
	self maps\so\zm_common\_zm_audio::do_player_playdialog(player_index, sound_to_play, 0.25);
}
// this is where zombies go into attack mode, and need different attributes set up
zombie_setup_attack_properties()
{
	self zombie_history( "zombie_setup_attack_properties()" );

	// allows zombie to attack again
	self.ignoreall = false; 

	// push the player out of the way so they use traversals in the house.
	self PushPlayer( true ); 

	self.pathEnemyFightDist = 64;
	self.meleeAttackDist = 64;
	
	//try to prevent always turning towards the enemy
	self.maxsightdistsqrd = 128 * 128;

	// turn off transition anims
	self.disableArrivals = true; 
	self.disableExits = true; 
}


// the seeker logic for zombies
find_flesh()
{
	self endon( "death" ); 
	level endon( "intermission" );

	if( level.intermission )
	{
		return;
	}

		self.ignore_player = undefined;

	self zombie_history( "find flesh -> start" );

	self.goalradius = 32;
	while( 1 )
	{

		// try to split the zombies up when the bunch up
		// see if a bunch zombies are already near my current target; if there's a bunch
		// and I'm still far enough away, ignore my current target and go after another one
//		near_zombies = getaiarray("axis");
//		same_enemy_count = 0;
//		for (i = 0; i < near_zombies.size; i++)
//		{
//			if ( isdefined( near_zombies[i] ) && isalive( near_zombies[i] ) )
//			{
//				if ( isdefined( near_zombies[i].favoriteenemy ) && isdefined( self.favoriteenemy ) 
//				&&	near_zombies[i].favoriteenemy == self.favoriteenemy )
//				{
//					if ( distancesquared( near_zombies[i].origin, self.favoriteenemy.origin ) < 225 * 225 
//					&&	 distancesquared( near_zombies[i].origin, self.origin ) > 525 * 525)
//					{
//						same_enemy_count++;
//					}
//				}
//			}
//		}
//		
//		if (same_enemy_count > 12)
//		{
//			self.ignore_player = self.favoriteenemy;
//		}
		
		players = getPlayers();
				
		// If playing single player, never ignore the player
		if( players.size == 1 )
		{
			self.ignore_player = undefined;
		}

		player = get_closest_valid_player( self.origin, self.ignore_player ); 
		
		if( !IsDefined( player ) )
		{
			self zombie_history( "find flesh -> can't find player, continue" );
			if( IsDefined( self.ignore_player ) )
			{
				self.ignore_player = undefined;
			}

			wait( 1 ); 
			continue; 
		}

		self.ignore_player = undefined;

		self.favoriteenemy = player;
		self thread zombie_pathing();

		self.zombie_path_timer = GetTime() + ( RandomFloatRange( 1, 3 ) * 1000 );
		while( GetTime() < self.zombie_path_timer )
		{
			wait( 0.1 );
		}

		self zombie_history( "find flesh -> bottom of loop" );

		debug_print( "Zombie is re-acquiring enemy, ending breadcrumb search" );
		self notify( "zombie_acquire_enemy" );
	}
}


zombie_pathing()
{
	self endon( "death" );
	self endon( "zombie_acquire_enemy" );
	level endon( "intermission" );

	assert( IsDefined( self.favoriteenemy ) );
	self.favoriteenemy endon( "disconnect" );

	self thread zombie_follow_enemy();
	self waittill( "bad_path" );

	debug_print( "Zombie couldn't path to player at origin: " + self.favoriteenemy.origin + " Falling back to breadcrumb system" );
	crumb_list = self.favoriteenemy.zombie_breadcrumbs;
	bad_crumbs = [];

	while( 1 )
	{
		if( !is_player_valid( self.favoriteenemy ) )
		{
			self.zombie_path_timer = 0;
			return;
		}

		goal = zombie_pathing_get_breadcrumb( self.favoriteenemy.origin, crumb_list, bad_crumbs, ( RandomInt( 100 ) < 20 ) );
		
		if ( !IsDefined( goal ) )
		{
			debug_print( "Zombie exhausted breadcrumb search" );
			goal = self.favoriteenemy.spectator_respawn.origin;
		}

		debug_print( "Setting current breadcrumb to " + goal );

		self.zombie_path_timer += 1000;
		self SetGoalPos( goal );
		self waittill( "bad_path" );

		debug_print( "Zombie couldn't path to breadcrumb at " + goal + " Finding next breadcrumb" );
		for( i = 0; i < crumb_list.size; i++ )
		{
			if( goal == crumb_list[i] )
			{
				bad_crumbs[bad_crumbs.size] = i;
				break;
			}
		}
	}
}

zombie_pathing_get_breadcrumb( origin, breadcrumbs, bad_crumbs, pick_random )
{
	assert( IsDefined( origin ) );
	assert( IsDefined( breadcrumbs ) );
	assert( IsArray( breadcrumbs ) );

	/#
		if ( pick_random )
		{
			debug_print( "Finding random breadcrumb" );
		}
	#/
			
	for( i = 0; i < breadcrumbs.size; i++ )
	{
		if ( pick_random )
		{
			crumb_index = RandomInt( breadcrumbs.size );
		}
		else
		{
			crumb_index = i;
		}
				
		if( crumb_is_bad( crumb_index, bad_crumbs ) )
		{
			continue;
		}

		return breadcrumbs[crumb_index];
	}

	return undefined;
}

crumb_is_bad( crumb, bad_crumbs )
{
	for ( i = 0; i < bad_crumbs.size; i++ )
	{
		if ( bad_crumbs[i] == crumb )
		{
			return true;
		}
	}

	return false;
}

jitter_enemies_bad_breadcrumbs( start_crumb )
{
	trace_distance = 35;
	jitter_distance = 2;
	
	index = start_crumb;
	
	while (isdefined(self.favoriteenemy.zombie_breadcrumbs[ index + 1 ]))
	{
		current_crumb = self.favoriteenemy.zombie_breadcrumbs[ index ];
		next_crumb = self.favoriteenemy.zombie_breadcrumbs[ index + 1 ];
		
		angles = vectortoangles(current_crumb - next_crumb);
		
		right = anglestoright(angles);
		left = anglestoright(angles + (0,180,0));
		
		dist_pos = current_crumb + vectorScale( right, trace_distance );
		
		trace = bulletTrace( current_crumb, dist_pos, true, undefined );
		vector = trace["position"];
		
		if (distance(vector, current_crumb) < 17 )
		{
			self.favoriteenemy.zombie_breadcrumbs[ index ] = current_crumb + vectorScale( left, jitter_distance );
			continue;
		}
		
		
		// try the other side
		dist_pos = current_crumb + vectorScale( left, trace_distance );
		
		trace = bulletTrace( current_crumb, dist_pos, true, undefined );
		vector = trace["position"];
		
		if (distance(vector, current_crumb) < 17 )
		{
			self.favoriteenemy.zombie_breadcrumbs[ index ] = current_crumb + vectorScale( right, jitter_distance );
			continue;
		}
		
		index++;
	}
	
}

zombie_follow_enemy()
{
	self endon( "death" );
	self endon( "zombie_acquire_enemy" );
	self endon( "bad_path" );
	
	level endon( "intermission" );

	while( 1 )
	{
		if( IsDefined( self.favoriteenemy ) )
		{
			self SetGoalPos( self.favoriteenemy.origin );
		}
		
		// PI_CHANGE_BEGIN
		// JMA - while on the zipline, get zipline destination and use it as the goal
		if( isDefined(level.script) && level.script == "nazi_zombie_sumpf" )
		{			
			if( isDefined(self.favoriteenemy.on_zipline) &&  self.favoriteenemy.on_zipline == true )
			{
				crumb_list = self.favoriteenemy.zombie_breadcrumbs;
				bad_crumbs = [];
				goal = zombie_pathing_get_breadcrumb( self.favoriteenemy.origin, crumb_list, bad_crumbs, 0 );
				if( isDefined(goal) )
					self SetGoalPos( goal );
			}		
		}
		// PI_CHANGE_END
		
		wait( 0.1 );
	}
}


// When a Zombie spawns, set his eyes to glowing.
zombie_eye_glow()
{
	if( IsDefined( level.zombie_eye_glow ) && !level.zombie_eye_glow )
	{
		return; 
	}

	if( !IsDefined( self ) )
	{
		return;
	}

	if(!isdefined(level._numZombEyeGlows))
	{
		level._numZombEyeGlows = 0;
	}
	
	if(level.zombie_eyes_limited && level._numZombEyeGlows > 8)
		return;

	if ( level.zombie_eyes_disabled )
	{
		return;
	}

	linkTag = "J_Eyeball_LE";
	fxModel = "tag_origin";
	fxTag = "tag_origin";

	// SRS 9/2/2008: only using one particle now per Barry's request;
	//  modified to be able to turn particle off
	
	self.fx_eye_glow = Spawn( "script_model", self GetTagOrigin( linkTag ) );
	self.fx_eye_glow.angles = self GetTagAngles( linkTag );
	self.fx_eye_glow SetModel( fxModel );
	self.fx_eye_glow LinkTo( self, linkTag );

	// TEMP for testing
	//self.fx_eye_glow thread maps\_debug::drawTagForever( fxTag );

	PlayFxOnTag( level._effect["eye_glow"], self.fx_eye_glow, fxTag );
	
	level._numZombEyeGlows ++;
}

// Called when either the Zombie dies or if his head gets blown off
zombie_eye_glow_stop()
{
	if( IsDefined( self.fx_eye_glow ) )
	{
		self.fx_eye_glow Delete();
		level._numZombEyeGlows --;
	}
}


//
// DEBUG
//

zombie_history( msg )
{
/#
	if( !IsDefined( self.zombie_history ) )
	{
		self.zombie_history = [];
	}

	self.zombie_history[self.zombie_history.size] = msg;
#/
}

/*
	Zombie Rise Stuff
*/

zombie_rise()
{
	self endon("death");
	self endon("no_rise");

	while(!IsDefined(self.do_rise))
	{
		wait_network_frame();
	}

	self do_zombie_rise();
}

/*
zombie_rise:
Zombies rise from the ground
*/
do_zombie_rise()
{
	self endon("death");

	self.zombie_rise_version = (RandomInt(99999) % 2) + 1;	// equally choose between version 1 and verson 2 of the animations
	if (self.zombie_move_speed != "walk")
	{
		// only do version 1 anims for "run" and "sprint"
		self.zombie_rise_version = 1;
	}

	self.in_the_ground = true;

	//self.zombie_rise_version = 1; // TESTING: override version

	self.anchor = spawn_temp_entity_delete_after_time( "script_origin", self.origin, undefined, "do_zombie_rise_anchor", 30 );
	self.anchor.angles = self.angles;
	self linkto(self.anchor);

	// JMA - this is used in swamp to only spawn risers in active player zones
	if( level.script == "nazi_zombie_sumpf" && IsDefined( level.zombie_rise_spawners ) )
	{
		spots = level.zombie_rise_spawners;
	}
	else
	{
		spots = GetStructArray("zombie_rise", "targetname");
	}

	if( spots.size < 1 )
	{
		self unlink();
		self.anchor delete();
		return;
	}
	else
	spot = random(spots);

	/#
	if (GetDVarInt("zombie_rise_test"))
	{
		spot = SpawnStruct();			// I know this never gets deleted, but it's just for testing
		spot.origin = (472, 240, 56);	// TEST LOCATION
		spot.angles = (0, 0, 0);
	}
	#/

	anim_org = spot.origin;
	anim_ang = spot.angles;

	//TODO: bbarnes: do a bullet trace to the ground so the structs don't have to be exactly on the ground.

	if (self.zombie_rise_version == 2)
	{
		anim_org = anim_org + (0, 0, -14);	// version 2 animation starts 14 units below the ground
	}
	else
	{
		anim_org = anim_org + (0, 0, -45);	// start the animation 45 units below the ground
	}

	//self Teleport(anim_org, anim_ang);	// we should get this working for MP

	self Hide();
	self.anchor moveto(anim_org, .05);
	self.anchor waittill("movedone");

	// face goal
	target_org = get_desired_origin();
	if (IsDefined(target_org))
	{
		anim_ang = VectorToAngles(target_org - self.origin);
		self.anchor RotateTo((0, anim_ang[1], 0), .05);
		self.anchor waittill("rotatedone");
	}

	self unlink();
	self.anchor delete();

	self thread hide_pop();	// hack to hide the pop when the zombie gets to the start position before the anim starts

	level thread zombie_rise_death(self, spot);
	spot thread zombie_rise_fx(self);

	//self animMode("nogravity");
	//self setFlaggedAnimKnoballRestart("rise", level.scr_anim["zombie"]["rise_walk"], %body, 1, .1, 1);	// no "noclip" mode for these anim functions

	self AnimScripted("rise", self.origin, self.angles, self get_rise_anim());
	self animscripts\shared::DoNoteTracks("rise", ::handle_rise_notetracks, undefined, spot);

	self notify("rise_anim_finished");
	spot notify("stop_zombie_rise_fx");
	self.in_the_ground = false;
	self notify("risen");
}

hide_pop()
{
	wait .5;
	self Show();
}

handle_rise_notetracks(note, spot)
{
	// the anim notetracks control which death anim to play
	// default to "deathin" (still in the ground)

	if (note == "deathout" || note == "deathhigh")
	{
		self.zombie_rise_death_out = true;
		self notify("zombie_rise_death_out");

		wait 2;
		spot notify("stop_zombie_rise_fx");
	}
}

/*
zombie_rise_death:
Track when the zombie should die, set the death anim, and stop the animscripted so he can die
*/
zombie_rise_death(zombie, spot)
{
	//self.nodeathragdoll = true;
	zombie.zombie_rise_death_out = false;

	zombie endon("rise_anim_finished");

	while (zombie.health > 1)	// health will only go down to 1 when playing animation with AnimScripted()
	{
		zombie waittill("damage", amount);
	}

	spot notify("stop_zombie_rise_fx");

	zombie.deathanim = zombie get_rise_death_anim();
	zombie StopAnimScripted();	// stop the anim so the zombie can die.  death anim is handled by the anim scripts.
}

/*
zombie_rise_fx:	 self is the script struct at the rise location
Play the fx as the zombie crawls out of the ground and thread another function to handle the dust falling
off when the zombie is out of the ground.
*/
zombie_rise_fx(zombie)
{
	self thread zombie_rise_dust_fx(zombie);
	self thread zombie_rise_burst_fx();
	playsoundatposition ("zombie_spawn", self.origin);
	zombie endon("death");
	self endon("stop_zombie_rise_fx");
	wait 1;
	if (zombie.zombie_move_speed != "sprint")
	{
		// wait longer before starting billowing fx if it's not a really fast animation
		wait 1;
	}
}

zombie_rise_burst_fx()
{
	self endon("stop_zombie_rise_fx");
	self endon("rise_anim_finished");
	
	if(IsDefined(self.script_noteworthy) && self.script_noteworthy == "in_water")
	{

		playfx(level._effect["rise_burst_water"],self.origin + ( 0,0,randomintrange(5,10) ) );
		wait(.25);
		playfx(level._effect["rise_billow_water"],self.origin + ( randomintrange(-10,10),randomintrange(-10,10),randomintrange(5,10) ) );
		
	}
	else
	{
		playfx(level._effect["rise_burst"],self.origin + ( 0,0,randomintrange(5,10) ) );
		wait(.25);
		playfx(level._effect["rise_billow"],self.origin + ( randomintrange(-10,10),randomintrange(-10,10),randomintrange(5,10) ) );


	}
	

	
	
	//burst_time = 10; // play dust fx for a max time
	//interval = randomfloatrange(.15,.45); // wait this time in between playing the effect
		
	//for (t = 0; t < burst_time; t += interval)
	//{
	//	wait interval;
	//}	
}

zombie_rise_dust_fx(zombie)
{
	dust_tag = "J_SpineUpper";
	
	self endon("stop_zombie_rise_dust_fx");
	self thread stop_zombie_rise_dust_fx(zombie);

	dust_time = 7.5; // play dust fx for a max time
	dust_interval = .1; //randomfloatrange(.1,.25); // wait this time in between playing the effect
	
	//TODO - add rising dust stuff ere
	if(IsDefined(self.script_noteworthy) && self.script_noteworthy == "in_water")
	{

		for (t = 0; t < dust_time; t += dust_interval)
		{
			PlayfxOnTag(level._effect["rise_dust_water"], zombie, dust_tag);
			wait dust_interval;
		}

	}
	else
	{
		for (t = 0; t < dust_time; t += dust_interval)
		{
		PlayfxOnTag(level._effect["rise_dust"], zombie, dust_tag);
		wait dust_interval;
		}
	}
}

stop_zombie_rise_dust_fx(zombie)
{
	zombie waittill("death");
	self notify("stop_zombie_rise_dust_fx");
}

/*
get_rise_anim:
Return a random rise animation based on a possible set of animations
*/
get_rise_anim()
{
	///* TESTING: put this block back in
	speed = self.zombie_move_speed;
	return random(level._zombie_rise_anims[self.zombie_rise_version][speed]);
	//*/

	//return %ai_zombie_traverse_ground_v1_crawlfast;
	//return %ai_zombie_traverse_ground_v2_walk;
	//return %ai_zombie_traverse_ground_v2_walk_altB;
}

/*
get_rise_death_anim:
Return a random death animation based on a possible set of animations
*/
get_rise_death_anim()
{
	possible_anims = [];

	if (self.zombie_rise_death_out)
	{
		possible_anims = level._zombie_rise_death_anims[self.zombie_rise_version]["out"];
	}
	else
	{
		possible_anims = level._zombie_rise_death_anims[self.zombie_rise_version]["in"];
	}

	return random(possible_anims);
}
