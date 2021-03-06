//Updates the mob's health from organs and mob damage variables
/mob/living/carbon/human/updatehealth()
	if(status_flags & GODMODE)
		health = maxHealth
		stat = CONSCIOUS
		return
	var/total_burn	= 0
	var/total_brute	= 0
	for(var/datum/organ/external/O in organs)	//hardcoded to streamline things a bit
		total_brute	+= O.brute_dam
		total_burn	+= O.burn_dam
	health = maxHealth - getOxyLoss() - getToxLoss() - getCloneLoss() - total_burn - total_brute
	//TODO: fix husking
	if( ((maxHealth - total_burn) < config.health_threshold_dead) && stat == DEAD) //100 only being used as the magic human max health number, feel free to change it if you add a var for it -- Urist
		ChangeToHusk()
	return

/mob/living/carbon/human/getBrainLoss()
	var/res = brainloss
	if(species && species.has_organ["brain"])
		var/datum/organ/internal/brain/sponge = internal_organs_by_name["brain"]
		if(!sponge)
			res += 200
		else
			if (sponge.is_bruised())
				res += 20
			if (sponge.is_broken())
				res += 50

		res = min(res,maxHealth*2)
		return res
	return 0

//These procs fetch a cumulative total damage from all organs
/mob/living/carbon/human/getBruteLoss()
	var/amount = 0
	for(var/datum/organ/external/O in organs)
		amount += O.brute_dam
	return amount

/mob/living/carbon/human/getFireLoss()
	var/amount = 0
	for(var/datum/organ/external/O in organs)
		amount += O.burn_dam
	return amount


/mob/living/carbon/human/adjustBruteLoss(var/amount)

	amount = amount * brute_damage_modifier

	if(INVOKE_EVENT(on_damaged, list("type" = BRUTE, "amount" = amount)))
		return 0

	if(amount > 0)
		take_overall_damage(amount, 0)
	else
		heal_overall_damage(-amount, 0)
	hud_updateflag |= 1 << HEALTH_HUD

/mob/living/carbon/human/adjustFireLoss(var/amount)
	amount = amount * burn_damage_modifier

	if(INVOKE_EVENT(on_damaged, list("type" = BURN, "amount" = amount)))
		return 0

	if(amount > 0)
		take_overall_damage(0, amount)
	else
		heal_overall_damage(0, -amount)
	hud_updateflag |= 1 << HEALTH_HUD

/mob/living/carbon/human/proc/adjustBruteLossByPart(var/amount, var/organ_name, var/obj/damage_source = null)
	amount = amount * brute_damage_modifier

	if(INVOKE_EVENT(on_damaged, list("type" = BRUTE, "amount" = amount)))
		return 0

	if (organ_name in organs_by_name)
		var/datum/organ/external/O = get_organ(organ_name)

		if(amount > 0)
			O.take_damage(amount, 0, sharp=damage_source.is_sharp(), edge=has_edge(damage_source), used_weapon=damage_source)
		else
			//if you don't want to heal robot organs, they you will have to check that yourself before using this proc.
			O.heal_damage(-amount, 0, internal=0, robo_repair=(O.status & ORGAN_ROBOT))

	hud_updateflag |= 1 << HEALTH_HUD

/mob/living/carbon/human/proc/adjustFireLossByPart(var/amount, var/organ_name, var/obj/damage_source = null)
	amount = amount * burn_damage_modifier

	if(INVOKE_EVENT(on_damaged, list("type" = BURN, "amount" = amount)))
		return 0

	if (organ_name in organs_by_name)
		var/datum/organ/external/O = get_organ(organ_name)

		if(amount > 0)
			O.take_damage(0, amount, sharp=damage_source.is_sharp(), edge=has_edge(damage_source), used_weapon=damage_source)
		else
			//if you don't want to heal robot organs, they you will have to check that yourself before using this proc.
			O.heal_damage(0, -amount, internal=0, robo_repair=(O.status & ORGAN_ROBOT))

	hud_updateflag |= 1 << HEALTH_HUD

/mob/living/carbon/human/Stun(amount)
	if(M_HULK in mutations)
		return
	..()

/mob/living/carbon/human/Weaken(amount)
	if(M_HULK in mutations)
		return
	..()

/mob/living/carbon/human/Paralyse(amount)
	if(M_HULK in mutations)
		return
	..()

/mob/living/carbon/human/adjustCloneLoss(var/amount)
	..()

	amount = amount * clone_damage_modifier

	if(INVOKE_EVENT(on_damaged, list("type" = CLONE, "amount" = amount)))
		return 0

	var/heal_prob = max(0, 80 - getCloneLoss())
	var/mut_prob = min(80, getCloneLoss()+10)
	if (amount > 0)
		if (prob(mut_prob))
			var/list/datum/organ/external/candidates = list()
			for (var/datum/organ/external/O in organs)
				if(!(O.status & ORGAN_MUTATED))
					candidates |= O
			if (candidates.len)
				var/datum/organ/external/O = pick(candidates)
				O.mutate()
				to_chat(src, "<span class = 'notice'>Something is not right with your [O.display_name]...</span>")
				return
	else
		if (prob(heal_prob))
			for (var/datum/organ/external/O in organs)
				if (O.status & ORGAN_MUTATED)
					O.unmutate()
					to_chat(src, "<span class = 'notice'>Your [O.display_name] is shaped normally again.</span>")
					return

	if (getCloneLoss() < 1)
		for (var/datum/organ/external/O in organs)
			if (O.status & ORGAN_MUTATED)
				O.unmutate()
				to_chat(src, "<span class = 'notice'>Your [O.display_name] is shaped normally again.</span>")
	hud_updateflag |= 1 << HEALTH_HUD

////////////////////////////////////////////

//Returns a list of damaged organs
/mob/living/carbon/human/proc/get_damaged_organs(var/brute, var/burn)
	var/list/datum/organ/external/parts = list()
	for(var/datum/organ/external/O in organs)
		if((brute && O.brute_dam) || (burn && O.burn_dam))
			parts += O
	return parts

//Returns a list of damageable organs
/mob/living/carbon/human/proc/get_damageable_organs()
	var/list/datum/organ/external/parts = list()
	for(var/datum/organ/external/O in organs)
		if(O.brute_dam + O.burn_dam < O.max_damage)
			parts += O
	return parts

//Heals ONE external organ, organ gets randomly selected from damaged ones.
//It automatically updates damage overlays if necesary
//It automatically updates health status
/mob/living/carbon/human/heal_organ_damage(var/brute, var/burn)
	var/list/datum/organ/external/parts = get_damaged_organs(brute,burn)
	if(!parts.len)
		return
	var/datum/organ/external/picked = pick(parts)
	if(picked.heal_damage(brute,burn))
		UpdateDamageIcon()
		hud_updateflag |= 1 << HEALTH_HUD
	updatehealth()


/*
In most cases it makes more sense to use apply_damage() instead! And make sure to check armour if applicable.
*/
//Damages ONE external organ, organ gets randomly selected from damagable ones.
//It automatically updates damage overlays if necesary
//It automatically updates health status
/mob/living/carbon/human/take_organ_damage(var/brute, var/burn, var/sharp = 0, var/edge = 0)
	var/list/datum/organ/external/parts = get_damageable_organs()
	if(!parts.len)
		return
	var/datum/organ/external/picked = pick(parts)
	if(picked.take_damage(brute,burn,sharp,edge))
		UpdateDamageIcon()
		hud_updateflag |= 1 << HEALTH_HUD
	updatehealth()
	//speech_problem_flag = 1


//Heal MANY external organs, in random order
/mob/living/carbon/human/heal_overall_damage(var/brute, var/burn)
	var/list/datum/organ/external/parts = get_damaged_organs(brute,burn)

	var/update = 0
	while(parts.len && (brute>0 || burn>0) )
		var/datum/organ/external/picked = pick(parts)

		var/brute_was = picked.brute_dam
		var/burn_was = picked.burn_dam

		update |= picked.heal_damage(brute,burn)

		brute -= (brute_was-picked.brute_dam)
		burn -= (burn_was-picked.burn_dam)

		parts -= picked
	updatehealth()
	hud_updateflag |= 1 << HEALTH_HUD
	//speech_problem_flag = 1
	if(update)
		UpdateDamageIcon()

// damage MANY external organs, in random order
/mob/living/carbon/human/take_overall_damage(var/brute, var/burn, var/sharp = 0, var/edge = 0, var/used_weapon = null)
	if(species && species.burn_mod)
		burn = burn*species.burn_mod
	if(species && species.brute_mod)
		brute = brute*species.brute_mod

	if(status_flags & GODMODE)
		return	//godmode
	var/list/datum/organ/external/parts = get_damageable_organs()
	var/update = 0
	while(parts.len && (brute>0 || burn>0) )
		var/datum/organ/external/picked = pick(parts)

		var/brute_was = picked.brute_dam
		var/burn_was = picked.burn_dam

		update |= picked.take_damage(brute,burn,sharp,edge,used_weapon)
		brute	-= (picked.brute_dam - brute_was)
		burn	-= (picked.burn_dam - burn_was)

		parts -= picked
	updatehealth()
	hud_updateflag |= 1 << HEALTH_HUD
	if(update)
		UpdateDamageIcon()


////////////////////////////////////////////

/*
This function restores the subjects blood to max.
*/
/mob/living/carbon/human/proc/restore_blood()
	if(!species.flags & NO_BLOOD)
		var/blood_volume = vessel.get_reagent_amount(BLOOD)
		vessel.add_reagent(BLOOD,560.0-blood_volume)


/*
This function restores all organs.
*/
/mob/living/carbon/human/restore_all_organs()
	for(var/datum/organ/external/current_organ in organs)
		current_organ.rejuvenate()

/mob/living/carbon/human/proc/HealDamage(zone, brute, burn)
	var/datum/organ/external/E = get_organ(zone)
	if(istype(E, /datum/organ/external))
		if (E.heal_damage(brute, burn))
			UpdateDamageIcon()
			hud_updateflag |= 1 << HEALTH_HUD
	else
		return 0
	return


/mob/living/carbon/human/proc/get_organ(var/zone)
	if(!zone)
		zone = LIMB_CHEST
	if (zone in list( "eyes", "mouth" ))
		zone = LIMB_HEAD
	return organs_by_name[zone]

/mob/living/carbon/human/apply_damage(var/damage = 0,var/damagetype = BRUTE, var/def_zone = null, var/blocked = 0, var/sharp = 0, var/edge = 0, var/obj/used_weapon = null, ignore_events = 0)

	//visible_message("Hit debug. [damage] | [damagetype] | [def_zone] | [blocked] | [sharp] | [used_weapon]")
	if((damagetype != BRUTE) && (damagetype != BURN))
		..(damage, damagetype, def_zone, blocked, ignore_events = ignore_events)
		return 1

	if(blocked >= 2)
		return 0

	var/datum/organ/external/organ = null
	if(isorgan(def_zone))
		organ = def_zone
	else
		if(!def_zone)
			def_zone = ran_zone(def_zone)
		organ = get_organ(check_zone(def_zone))
	if(!organ)
		return 0

	if(blocked)
		damage = (damage/(blocked+1))

	if(!ignore_events && INVOKE_EVENT(on_damaged, list("type" = damagetype, "amount" = damage)))
		return 0

	switch(damagetype)
		if(BRUTE)
			damageoverlaytemp = 20
			damage = damage * brute_damage_modifier

			if(organ.take_damage(damage, 0, sharp, edge, used_weapon))
				UpdateDamageIcon(1)
		if(BURN)
			damageoverlaytemp = 20
			damage = damage * burn_damage_modifier

			if(organ.take_damage(0, damage, sharp, edge, used_weapon))
				UpdateDamageIcon(1)

	// Will set our damageoverlay icon to the next level, which will then be set back to the normal level the next mob.Life().
	updatehealth()
	hud_updateflag |= 1 << HEALTH_HUD

	//Embedded projectile code.
	if(!organ)
		return
/*/vg/ EDIT
	if(istype(used_weapon,/obj/item/weapon))
		var/obj/item/weapon/W = used_weapon  //Sharp objects will always embed if they do enough damage.
		if( (damage > (10*W.w_class)) && ( (sharp && !ismob(W.loc)) || prob(damage/W.w_class) ) )
			if(!istype(W, /obj/item/weapon/kitchen/utensil/knife/large/butch/meatcleaver))
				organ.implants += W
				visible_message("<span class='danger'>\The [W] sticks in the wound!</span>")
				W.add_blood(src)
				if(ismob(W.loc))
					var/mob/living/H = W.loc
					H.drop_item(W, src)
				W.forceMove(src)
*/
	if(istype(used_weapon,/obj/item/projectile/bullet)) //We don't want to use the actual projectile item, so we spawn some shrapnel.
		var/obj/item/projectile/bullet/P = used_weapon
		if(prob(75) && damagetype == BRUTE && P.embed)
			var/obj/item/weapon/shard/shrapnel/S = new()
			S.name = "[P.name] shrapnel"
			S.desc = "[S.desc] It looks like it was fired from [P.shot_from]."
			S.forceMove(src)
			organ.implants += S
			visible_message("<span class='danger'>The projectile sticks in the wound!</span>")
			S.add_blood(src)
	if(istype(used_weapon,/obj/item/projectile/flare)) //We want them to carry the flare, not a projectile
		var/obj/item/projectile/flare/F = used_weapon
		if(damagetype == BURN && F.embed && (istype(F.shot_from, /obj/item/weapon/gun/projectile/flare/syndicate) || istype(F.shot_from, /obj/item/weapon/gun/lawgiver)) && prob(75)) //only syndicate guns are dangerous, except for the lawgiver, which is intended to fire incendiary rounds
			var/obj/item/device/flashlight/flare/FS = new
			FS.name = "shot [FS.name]"
			FS.desc = "[FS.desc]. It looks like it was fired from [F.shot_from]."
			FS.forceMove(src)
			organ.implants += FS
			visible_message("<span class='danger'>The flare sticks in the wound!</span>")
			FS.add_blood(src)
			FS.luminosity = 4 //not so bright, because it's inside them
			FS.Light(src) //Now they glow, because the flare is lit
			if(prob(80)) //tends to happen, which is good
				visible_message("<span class='danger'><b>[name]</b> bursts into flames!</span>", "<span class='danger'>You burst into flames!</span>")
				on_fire = 1
				adjust_fire_stacks(0.5) //as seen in ignite code
				update_icon = 1
			qdel(F)
	return 1

//Adds cancer, including stage of cancer and limb
//Right now cancer is adminbus only. You can inflict it via the full (old) Player Panel and all "prayer types" (includes Centcomm message)
//Of course, should it ever come back for realsies, that's the right way to do it. But let's not be silly now
//IMPORTANT NOTE: Currently only works on external organs, because the person who wrote organ code has brain cancer, hopefully I will sweep back to fix this in a later PR
//Since I'd have to change hundreds of procs going through organs, that's not something I'll do now
/mob/living/carbon/human/proc/add_cancer(var/stage = 1, var/target)

	var/datum/organ/picked_organ
	if(target)
		picked_organ = organs_by_name["[target]"]
	else
		picked_organ = pick(organs)

	if(picked_organ)
		picked_organ.cancer_stage += stage //This can pick a limb which already has cancer, in which case it will add to it
