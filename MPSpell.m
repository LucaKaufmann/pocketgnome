//
//  MPSpell.m
//  Pocket Gnome
//
//  Created by Coding Monkey on 4/15/10.
//  Copyright 2010 Savory Software, LLC. All rights reserved.
//

#import "MPSpell.h"
#import "Spell.h"
#import "SpellController.h"
#import "PatherController.h"
#import "PlayerDataController.h"
#import "BotController.h"
#import "Aura.h"
#import "AuraController.h"


@implementation MPSpell
@synthesize mySpell, name, listIDs, listBuffIDs, botController, spellController;


- (id) init {
	
	if ((self = [super init])) {
		
		self.name = nil;
		self.mySpell = nil;
		spellID = 0;
		currentRank = 0;
		self.listIDs = [NSMutableArray array];
		self.listBuffIDs = [NSMutableArray array];
		
		
		self.botController = [[PatherController	sharedPatherController] botController];
		self.spellController = [SpellController sharedSpells];
	}
	return self;
}


- (void) dealloc
{
	[name release];
    [mySpell release];
	[listIDs release];
	[listBuffIDs release];
	[botController release];
	[spellController release];

    [super dealloc];
}


#pragma mark -



- (void) addID: (int) anID {

	[self.listIDs addObject:[NSNumber numberWithInt:anID]]; 
}



-(BOOL) canCast {

	if (mySpell == nil) {
		return NO;
	}
	
	
	return YES;
}


-(BOOL) cast {
	
	return [botController performAction:spellID];
	
}



- (void) scanForSpell {
	
	Spell *foundSpell = nil;
	
	
	// scan by registered ID's
	int rank = 1;
	int foundRank = 0;
	for( NSNumber *currID in listIDs ) {
		
		PGLog(@"    Rank %d : id[%d] ", rank, [currID intValue]);
		
		for(Spell *spell in  [spellController playerSpells]) {
			
			if ( [currID intValue] == [[spell ID] intValue]) {
				
				// we found this spell
				PGLog( @"       --> Found in player spells ");
				foundSpell = spell;
				foundRank = rank;
				break;
			}
		}
		
		rank ++;
		
	}
	
	
	if (foundSpell) {
		
		if (foundRank != currentRank) {
			PGLog(@"   UPDATED Spell:  %@ Rank %d", name, foundRank);
		}
		
		self.mySpell = foundSpell;
		spellID = [[foundSpell ID] intValue];
		currentRank = foundRank;
		
	} else {
		
		PGLog(@"     == Spell[%@] not found after scanning", name);
	}
	
	
}


- (void) loadPlayerSettings {
	
	self.mySpell = [spellController playerSpellForName:name];
	
	
	// if mySpell == nil
	if (mySpell == nil) {
		
		
		PGLog( @" spell[%@] not found by name ... scanning by IDs:", name);
		[self scanForSpell];
		
	} else {
		
		spellID = [[mySpell ID] intValue];
		currentRank = 0;
		int rank = 1;
		for( NSNumber *currID in listIDs ) {
			
			if ( [currID intValue] == spellID) {
				currentRank = rank;
				break;
			}
			rank++;
		}
	}
	
	PGLog(@"     == spellID[%@] id[%d] rank[%d]",name,  spellID, currentRank);
	// end if
}


#pragma mark -
#pragma mark Aura Checks


- (BOOL) unitHasBuff: (Unit *)unit {
	
	return [[AuraController sharedController] unit:unit hasBuff:spellID];
	
}


- (BOOL) unitHasDebuff: (Unit *)unit {
	
	return [[AuraController sharedController] unit:unit hasDebuff:spellID];
	
}


- (BOOL) unitHasMyBuff: (Unit *)unit {

	GUID myGUID = [[PlayerDataController sharedController] GUID];
	
	for(Aura *aura in [[AuraController sharedController] aurasForUnit: unit idsOnly: NO]) {
        if((aura.entryID == spellID) && (!aura.isDebuff) && (aura.guid == myGUID))
            return aura.stacks ? aura.stacks : YES;
    }
	return NO;
	
}



- (BOOL) unitHasMyDebuff: (Unit *)unit {
	
	GUID myGUID = [[PlayerDataController sharedController] GUID];
	
	for(Aura *aura in [[AuraController sharedController] aurasForUnit: unit idsOnly: NO]) {
        if((aura.entryID == spellID) && (aura.isDebuff) && (aura.guid == myGUID))
            return aura.stacks ? aura.stacks : YES;
    }
	return NO;
	
}


#pragma mark -



+ (id) spell {
	
	MPSpell *newSpell = [[MPSpell alloc] init];
	return [newSpell autorelease];
}





////
//// Physical
////

+ (id) autoAttack {
	
	MPSpell *newSpell = [MPSpell spell];
	[newSpell setName:@"Auto Attack"];
	[newSpell addID:  6603];  
	
	[newSpell loadPlayerSettings];
	
	return newSpell;
	
}



+ (id) shootWeapon {
	
	MPSpell *newSpell = [MPSpell spell];
	[newSpell setName:@"Shoot Weapon"];
	[newSpell addID:  3018]; //75 
	
	[newSpell loadPlayerSettings];
	
	return newSpell;
	
}



+ (id) shootWand {
	
	MPSpell *newSpell = [MPSpell spell];
	[newSpell setName:@"Shoot Wand"];
	[newSpell addID:  5019];  
	
	[newSpell loadPlayerSettings];
	
	return newSpell;
	
}




////
//// Druid Spells
////



+ (id) abolishPoison {
	
	MPSpell *newSpell = [MPSpell spell];
	[newSpell setName:@"Abolish Poison"];
	[newSpell addID:  2893];  // only 1 rank
	[newSpell loadPlayerSettings];
	
	return newSpell;
}



+ (id) curePoison {
	
	MPSpell *newSpell = [MPSpell spell];
	[newSpell setName:@"Cure Poison"];
	[newSpell addID:  8946];  // only 1 rank
	[newSpell loadPlayerSettings];
	
	return newSpell;
}



+ (id) faerieFire {
	
	MPSpell *newSpell = [MPSpell spell];
	[newSpell setName:@"Faerie Fire"];
	[newSpell addID:  770];  // only 1 rank
	[newSpell loadPlayerSettings];
	
	return newSpell;
}



+ (id) healingTouch {
	
	MPSpell *newSpell = [MPSpell spell];
	[newSpell setName:@"Healing Touch"];
	[newSpell addID:  5185];  // Rank 1
	[newSpell addID:  5186];  // Rank 2
	[newSpell addID:  5187];  // Rank 3
	[newSpell addID:  5188];  // Rank 4
	[newSpell addID:  5189];  // Rank 5
	[newSpell addID:  6778];  // Rank 6
	[newSpell addID:  8903];  // Rank 7
	[newSpell addID:  9758];  // Rank 8
	[newSpell addID:  9888];  // Rank 9
	[newSpell addID:  9889];  // Rank 10
	[newSpell addID: 25297];  // Rank 11
	[newSpell addID: 26978];  // Rank 12
	[newSpell addID: 26979];  // Rank 13
	[newSpell addID: 48377];  // Rank 14
	[newSpell addID: 48378];  // Rank 15
	[newSpell loadPlayerSettings];
	
	return newSpell;
}



+ (id) insectSwarm {
	
	MPSpell *newSpell = [MPSpell spell];
	[newSpell setName:@"Insect Swarm"];
	[newSpell addID:  5570];  // Rank 1
	[newSpell addID: 24974];  // Rank 2
	[newSpell addID: 24975];  // Rank 3
	[newSpell addID: 24976];  // Rank 4
	[newSpell addID: 24977];  // Rank 5
	[newSpell addID: 27013];  // Rank 6
	[newSpell addID: 48468];  // Rank 7
	
	[newSpell loadPlayerSettings];
	
	return newSpell;
}



+ (id) innervate {
	
	MPSpell *newSpell = [MPSpell spell];
	[newSpell setName:@"Innervate"];
	[newSpell addID: 29166];  // only 1 Rank 
	
	[newSpell loadPlayerSettings];
	
	return newSpell;
}



+ (id) moonfire {
	
	MPSpell *newSpell = [MPSpell spell];
	[newSpell setName:@"Moonfire"];
	[newSpell addID:  8921];  // Rank 1
	[newSpell addID:  8924];  // Rank 2
	[newSpell addID:  8925];  // Rank 3
	[newSpell addID:  8926];  // Rank 4
	[newSpell addID:  8927];  // Rank 5
	[newSpell addID:  8928];  // Rank 6
	[newSpell addID:  8929];  // Rank 7
	[newSpell addID:  9833];  // Rank 8
	[newSpell addID:  9834];  // Rank 9
	[newSpell addID:  9835];  // Rank 10
	[newSpell addID: 26987];  // Rank 11
	[newSpell addID: 26988];  // Rank 12
	[newSpell addID: 48462];  // Rank 13
	[newSpell addID: 48463];  // Rank 14
	[newSpell loadPlayerSettings];
	
	return newSpell;
}



+ (id) motw {
	
	MPSpell *newSpell = [MPSpell spell];
	[newSpell setName:@"Mark of the Wild"];
	[newSpell addID: 1126];  // Rank 1
	[newSpell addID: 5232];  // Rank 2
	[newSpell addID: 6756];  // Rank 3
	[newSpell addID: 5234];  // Rank 4 (not a typo)
	[newSpell addID: 8907];  // Rank 5
	[newSpell addID: 9884];  // Rank 6
	[newSpell addID: 9885];  // Rank 7
	[newSpell addID:26990];  // Rank 8
	[newSpell addID:48469];  // Rank 9
	[newSpell loadPlayerSettings];
	
	return newSpell;
}



+ (id) regrowth {
	
	MPSpell *newSpell = [MPSpell spell];
	[newSpell setName:@"Regrowth"];
	[newSpell addID:  8936];  // Rank 1
	[newSpell addID:  8938];  // Rank 2
	[newSpell addID:  8939];  // Rank 3
	[newSpell addID:  8940];  // Rank 4
	[newSpell addID:  8941];  // Rank 5
	[newSpell addID:  9750];  // Rank 6
	[newSpell addID:  9856];  // Rank 7
	[newSpell addID:  9857];  // Rank 8
	[newSpell addID:  9858];  // Rank 9
	[newSpell addID: 26980];  // Rank 10
	[newSpell addID: 48442];  // Rank 11
	[newSpell addID: 48443];  // Rank 12
	[newSpell loadPlayerSettings];
	
	return newSpell;
}



+ (id) rejuvenation {
	
	MPSpell *newSpell = [MPSpell spell];
	[newSpell setName:@"Rejuvenation"];
	[newSpell addID:  774];  // Rank 1
	[newSpell addID: 1058];  // Rank 2
	[newSpell addID: 1430];  // Rank 3
	[newSpell addID: 2090];  // Rank 4
	[newSpell addID: 2091];  // Rank 5
	[newSpell addID: 3627];  // Rank 6
	[newSpell addID: 8910];  // Rank 7
	[newSpell addID: 9839];  // Rank 8
	[newSpell addID: 9840];  // Rank 9
	[newSpell addID: 9841];  // Rank 10
	[newSpell addID:25299];  // Rank 11
	[newSpell addID:26981];  // Rank 12
	[newSpell addID:26982];  // Rank 13
	[newSpell addID:48440];  // Rank 14
	[newSpell addID:48441];  // Rank 15
	[newSpell loadPlayerSettings];
	
	return newSpell;
}



+ (id) removeCurseDruid {
	
	MPSpell *newSpell = [MPSpell spell];
	[newSpell setName:@"Remove Curse"];
	[newSpell addID:  2782];  // only 1 Rank

	[newSpell loadPlayerSettings];
	
	return newSpell;
}



+ (id) starfire {
	
	MPSpell *newSpell = [MPSpell spell];
	[newSpell setName:@"Starfire"];
	[newSpell addID:  2912];  // Rank 1
	[newSpell addID:  8949];  // Rank 2
	[newSpell addID:  8950];  // Rank 3
	[newSpell addID:  8951];  // Rank 4
	[newSpell addID:  9875];  // Rank 5
	[newSpell addID:  9876];  // Rank 6
	[newSpell addID: 25298];  // Rank 7
	[newSpell addID: 26986];  // Rank 8
	[newSpell addID: 48464];  // Rank 9
	[newSpell addID: 48465];  // Rank 10
	[newSpell loadPlayerSettings];
	
	return newSpell;
}



+ (id) thorns {
	
	MPSpell *newSpell = [MPSpell spell];
	[newSpell setName:@"Thorns"];
	[newSpell addID:  467];  // Rank 1
	[newSpell addID:  782];  // Rank 2
	[newSpell addID: 1075];  // Rank 3
	[newSpell addID: 8914];  // Rank 4
	[newSpell addID: 9756];  // Rank 5
	[newSpell addID: 9910];  // Rank 6
	[newSpell addID:26992];  // Rank 7
	[newSpell addID:53307];  // Rank 8
	[newSpell loadPlayerSettings];
	
	return newSpell;
}



+ (id) wrath {

	MPSpell *newSpell = [MPSpell spell];
	[newSpell setName:@"Wrath"];
	[newSpell addID: 5176];  // Rank 1
	[newSpell addID: 5177];  // Rank 2
	[newSpell addID: 5178];  // Rank 3
	[newSpell addID: 5179];  // Rank 4
	[newSpell addID: 5180];  // Rank 5
	[newSpell addID: 6780];  // Rank 6
	[newSpell addID: 8905];  // Rank 7
	[newSpell addID: 9912];  // Rank 8
	[newSpell addID:26984];  // Rank 9
	[newSpell addID:26985];  // Rank 10
	[newSpell addID:48459];  // Rank 11
	[newSpell addID:48461];  // Rank 12
	[newSpell loadPlayerSettings];
	
	return newSpell;
}




////
//// Hunter Spells
////


+ (id) arcaneShot {
	
	MPSpell *newSpell = [MPSpell spell];
	[newSpell setName:@"Arcane Shot"];
	[newSpell addID:  3044];  // Rank 1
	[newSpell addID: 14281];  // Rank 2
	[newSpell addID: 14282];  // Rank 3
	[newSpell addID: 14283];  // Rank 4
	[newSpell addID: 14284];  // Rank 5
	[newSpell addID: 14285];  // Rank 6
	[newSpell addID: 14286];  // Rank 7
	[newSpell addID: 14287];  // Rank 8
	[newSpell addID: 27019];  // Rank 9
	[newSpell addID: 49044];  // Rank 10
	[newSpell addID: 49055];  // Rank 11
	
	
	[newSpell loadPlayerSettings];
	
	return newSpell;
}



+ (id) aspectHawk {
	
	MPSpell *newSpell = [MPSpell spell];
	[newSpell setName:@"Aspect of the Hawk"];
	[newSpell addID:  13165]; // Rank 1
	[newSpell addID:  14318]; // Rank 2
	[newSpell addID:  14319]; // Rank 3
	[newSpell addID:  14320]; // Rank 4
	[newSpell addID:  14321]; // Rank 5
	[newSpell addID:  14322]; // Rank 6
	[newSpell addID:  25296]; // Rank 7
	[newSpell addID:  27044]; // Rank 8
	
	[newSpell loadPlayerSettings];
	
	return newSpell;
	
}



+ (id) aspectMonkey {
	
	MPSpell *newSpell = [MPSpell spell];
	[newSpell setName:@"Aspect of the Monkey"];
	[newSpell addID:  13163]; 
	
	[newSpell loadPlayerSettings];
	
	return newSpell;
	
}



+ (id) aspectViper {
	
	MPSpell *newSpell = [MPSpell spell];
	[newSpell setName:@"Aspect of the Viper"];
	[newSpell addID:  34074]; 
	
	[newSpell loadPlayerSettings];
	
	return newSpell;
	
}



+ (id) autoShot {
	
	MPSpell *newSpell = [MPSpell spell];
	[newSpell setName:@"Auto Shot"];
	[newSpell addID:  75]; 
	
	[newSpell loadPlayerSettings];
	
	return newSpell;
	
}




+ (id) huntersMark {
	
	MPSpell *newSpell = [MPSpell spell];
	[newSpell setName:@"Hunters Mark"];
	[newSpell addID:  1130]; // Rank 1
	[newSpell addID: 14323]; // Rank 2
	[newSpell addID: 14324]; // Rank 3
	[newSpell addID: 14325]; // Rank 4
	[newSpell addID: 53338]; // Rank 2
	
	
	[newSpell loadPlayerSettings];
	
	return newSpell;
	
}




+ (id) mendPet {
	
	MPSpell *newSpell = [MPSpell spell];
	[newSpell setName:@"Mend Pet"];
	[newSpell addID:   136]; // Rank 1
	[newSpell addID:  3111]; // Rank 2
	[newSpell addID:  3661]; // Rank 3
	[newSpell addID:  3662]; // Rank 4
	[newSpell addID: 13542]; // Rank 5
	[newSpell addID: 13543]; // Rank 6
	[newSpell addID: 13544]; // Rank 7
	[newSpell addID: 27046]; // Rank 8
	[newSpell addID: 48989]; // Rank 9
	[newSpell addID: 48990]; // Rank 10
	
	
	[newSpell loadPlayerSettings];
	
	return newSpell;
	
}




+ (id) raptorStrike {
	
	MPSpell *newSpell = [MPSpell spell];
	[newSpell setName:@"Raptor Strike"];
	[newSpell addID:  2973]; // Rank 1
	[newSpell addID: 14260]; // Rank 2
	[newSpell addID: 14261]; // Rank 3
	[newSpell addID: 14262]; // Rank 4
	[newSpell addID: 14263]; // Rank 5
	[newSpell addID: 14264]; // Rank 6
	[newSpell addID: 14265]; // Rank 7
	[newSpell addID: 14266]; // Rank 8
	[newSpell addID: 27014]; // Rank 9
	[newSpell addID: 48995]; // Rank 10
	[newSpell addID: 48996]; // Rank 11
	
	
	[newSpell loadPlayerSettings];
	
	return newSpell;
	
}




+ (id) serpentSting {
	
	MPSpell *newSpell = [MPSpell spell];
	[newSpell setName:@"Serpent Sting"];
	[newSpell addID:  1978]; // Rank 1
	[newSpell addID: 13549]; // Rank 2
	[newSpell addID: 13550]; // Rank 3
	[newSpell addID: 13551]; // Rank 4
	[newSpell addID: 13552]; // Rank 5
	[newSpell addID: 13553]; // Rank 6
	[newSpell addID: 13554]; // Rank 7
	[newSpell addID: 13555]; // Rank 8
	[newSpell addID: 25295]; // Rank 9
	[newSpell addID: 27016]; // Rank 10
	[newSpell addID: 49000]; // Rank 11
	[newSpell addID: 49001]; // Rank 12
	
	
	[newSpell loadPlayerSettings];
	
	return newSpell;
	
}




////
//// Priest Spells
////


+ (id) cureDisease {
	
	MPSpell *newSpell = [MPSpell spell];
	[newSpell setName:@"Cure Disease"];
	[newSpell addID:  528];  // Rank 1
	
	[newSpell loadPlayerSettings];
	
	return newSpell;
}



+ (id) devouringPlague {
	
	MPSpell *newSpell = [MPSpell spell];
	[newSpell setName:@"Devouring Plague"];
	[newSpell addID:  2944];  // Rank 1
	[newSpell addID: 19276];  // Rank 2
	[newSpell addID: 19277];  // Rank 3
	[newSpell addID: 19278];  // Rank 4
	[newSpell addID: 19279];  // Rank 5
	[newSpell addID: 19280];  // Rank 6
	[newSpell addID: 25467];  // Rank 7
	[newSpell addID: 48299];  // Rank 8
	[newSpell addID: 48300];  // Rank 9
	
	[newSpell loadPlayerSettings];
	
	return newSpell;
}



+ (id) dispelMagic {
	
	MPSpell *newSpell = [MPSpell spell];
	[newSpell setName:@"Dispel Magic"];
	[newSpell addID:  527];  // Rank 1
	[newSpell addID:  988];  // Rank 2
	
	[newSpell loadPlayerSettings];
	
	return newSpell;
}



+ (id) divineSpirit {
	
	MPSpell *newSpell = [MPSpell spell];
	[newSpell setName:@"Divine Spirit"];
	[newSpell addID:  14752];  // Rank 1
	[newSpell addID:  14818];  // Rank 2
	[newSpell addID:  14819];  // Rank 3
	[newSpell addID:  27841];  // Rank 4
	[newSpell addID:  25312];  // Rank 5
	[newSpell addID:  48073];  // Rank 6
	
	[newSpell loadPlayerSettings];
	
	return newSpell;
}



+ (id) fade {
	
	MPSpell *newSpell = [MPSpell spell];
	[newSpell setName:@"Fade"];
	[newSpell addID: 586];  // (only 1 rank)
	[newSpell loadPlayerSettings];
	
	return newSpell;
}



+ (id) flashHeal {
	
	MPSpell *newSpell = [MPSpell spell];
	[newSpell setName:@"Flash Heal"];
	[newSpell addID:   2061];  // Rank 1
	[newSpell addID:   9472];  // Rank 2
	[newSpell addID:   9473];  // Rank 3
	[newSpell addID:   9474];  // Rank 4
	[newSpell addID:  10915];  // Rank 5
	[newSpell addID:  10916];  // Rank 6
	[newSpell addID:  10917];  // Rank 7
	[newSpell addID:  25233];  // Rank 8
	[newSpell addID:  25235];  // Rank 9
	[newSpell addID:  48070];  // Rank 10
	[newSpell addID:  48071];  // Rank 11
	
	[newSpell loadPlayerSettings];
	
	return newSpell;
}



+ (id) heal {
	
	MPSpell *newSpell = [MPSpell spell];
	[newSpell setName:@"Heal"];
	[newSpell addID:  2050];  // Lesser Heal (Rank 1)
	[newSpell addID:  2052];  // Lesser Heal (Rank 2)
	[newSpell addID:  2053];  // Lesser Heal (Rank 3)
	[newSpell addID:  2054];  // Heal (Rank 1)
	[newSpell addID:  2055];  // Heal (Rank 2)
	[newSpell addID:  6063];  // Heal (Rank 3)
	[newSpell addID:  6064];  // Heal (Rank 4)
	[newSpell addID:  2060];  // Greater Heal (Rank 1)
	[newSpell addID: 10963];  // Greater Heal (Rank 2)
	[newSpell addID: 10964];  // Greater Heal (Rank 3)
	[newSpell addID: 10965];  // Greater Heal (Rank 4)
	[newSpell addID: 25314];  // Greater Heal (Rank 5)
	[newSpell addID: 25210];  // Greater Heal (Rank 6)
	[newSpell addID: 25213];  // Greater Heal (Rank 7)
	[newSpell addID: 48062];  // Greater Heal (Rank 8)
	[newSpell addID: 48063];  // Greater Heal (Rank 9)
	
	[newSpell loadPlayerSettings];
	
	return newSpell;
}



+ (id) holyFire {
	
	MPSpell *newSpell = [MPSpell spell];
	[newSpell setName:@"Holy Fire"];
	[newSpell addID:  14914];  // Rank 1
	[newSpell addID:  15262];  // Rank 2
	[newSpell addID:  15263];  // Rank 3
	[newSpell addID:  15264];  // Rank 4
	[newSpell addID:  15265];  // Rank 5
	[newSpell addID:  15266];  // Rank 6
	[newSpell addID:  15267];  // Rank 7
	[newSpell addID:  15261];  // Rank 8
	[newSpell addID:  25384];  // Rank 9
	[newSpell addID:  48134];  // Rank 10
	[newSpell addID:  48135];  // Rank 11
	
	[newSpell loadPlayerSettings];
	
	return newSpell;
}



+ (id) pwFort {
	
	MPSpell *newSpell = [MPSpell spell];
	[newSpell setName:@"Power Word: Fortitude"];
	[newSpell addID:  1243];  // Rank 1
	[newSpell addID:  1244];  // Rank 2
	[newSpell addID:  1245];  // Rank 3
	[newSpell addID:  2791];  // Rank 4
	[newSpell addID: 10937];  // Rank 5
	[newSpell addID: 10938];  // Rank 6
	[newSpell addID: 25389];  // Rank 7
	[newSpell addID: 48161];  // Rank 8
	
	[newSpell loadPlayerSettings];
	
	return newSpell;
}



+ (id) pwShield {
	
	MPSpell *newSpell = [MPSpell spell];
	[newSpell setName:@"Power Word: Shield"];
	[newSpell addID:    17];  // Rank 1
	[newSpell addID:   592];  // Rank 2
	[newSpell addID:   600];  // Rank 3
	[newSpell addID:  3747];  // Rank 4
	[newSpell addID:  6065];  // Rank 5
	[newSpell addID:  6066];  // Rank 6
	[newSpell addID: 10898];  // Rank 7
	[newSpell addID: 10899];  // Rank 8
	[newSpell addID: 10900];  // Rank 9
	[newSpell addID: 10901];  // Rank 10
	[newSpell addID: 25217];  // Rank 11
	[newSpell addID: 25218];  // Rank 12
	[newSpell addID: 48065];  // Rank 13
	[newSpell addID: 48066];  // Rank 14
	
	[newSpell loadPlayerSettings];
	
	return newSpell;
}



+ (id) renew {
	
	MPSpell *newSpell = [MPSpell spell];
	[newSpell setName:@"Renew"];
	[newSpell addID:   139];  // Rank 1
	[newSpell addID:  6074];  // Rank 2
	[newSpell addID:  6075];  // Rank 3
	[newSpell addID:  6076];  // Rank 4
	[newSpell addID:  6077];  // Rank 5
	[newSpell addID:  6078];  // Rank 6
	[newSpell addID: 10927];  // Rank 7
	[newSpell addID: 10928];  // Rank 8
	[newSpell addID: 10929];  // Rank 9
	[newSpell addID: 25315];  // Rank 10
	[newSpell addID: 25221];  // Rank 11
	[newSpell addID: 25222];  // Rank 12
	[newSpell addID: 48067];  // Rank 13
	[newSpell addID: 48068];  // Rank 14
	
	[newSpell loadPlayerSettings];
	
	return newSpell;
}



+ (id) resurrection {
	
	MPSpell *newSpell = [MPSpell spell];
	[newSpell setName:@"Resurrection"];
	[newSpell addID:  2006];  // Rank 1
	[newSpell addID:  2010];  // Rank 2
	[newSpell addID: 10880];  // Rank 3
	[newSpell addID: 10881];  // Rank 4
	[newSpell addID: 20770];  // Rank 5
	[newSpell addID: 25435];  // Rank 6
	[newSpell addID: 48171];  // Rank 7
	
	[newSpell loadPlayerSettings];
	
	return newSpell;
}



+ (id) smite {
	
	MPSpell *newSpell = [MPSpell spell];
	[newSpell setName:@"Smite"];
	[newSpell addID:   585];  // Rank 1
	[newSpell addID:   591];  // Rank 2
	[newSpell addID:   598];  // Rank 3
	[newSpell addID:   984];  // Rank 4
	[newSpell addID:  1004];  // Rank 5
	[newSpell addID:  6060];  // Rank 6
	[newSpell addID: 10933];  // Rank 7
	[newSpell addID: 10934];  // Rank 8
	[newSpell addID: 25363];  // Rank 9
	[newSpell addID: 25364];  // Rank 10
	[newSpell addID: 48122];  // Rank 11
	[newSpell addID: 48123];  // Rank 12
	
	[newSpell loadPlayerSettings];
	
	return newSpell;
}



+ (id) swPain {
	
	MPSpell *newSpell = [MPSpell spell];
	[newSpell setName:@"Shadow Word: Pain"];
	[newSpell addID:   589];  // Rank 1
	[newSpell addID:   594];  // Rank 2
	[newSpell addID:   970];  // Rank 3
	[newSpell addID:   992];  // Rank 4
	[newSpell addID:  2767];  // Rank 5
	[newSpell addID: 10892];  // Rank 6
	[newSpell addID: 10893];  // Rank 7
	[newSpell addID: 10894];  // Rank 8
	[newSpell addID: 25367];  // Rank 9
	[newSpell addID: 25368];  // Rank 10
	[newSpell addID: 48124];  // Rank 11
	[newSpell addID: 48125];  // Rank 12
	
	[newSpell loadPlayerSettings];
	
	return newSpell;
}



@end
