//
//  BotController.m
//  Pocket Gnome
//
//  Created by Jon Drummond on 1/14/08.
//  Copyright 2008 Savory Software, LLC. All rights reserved.
//

#import "BotController.h"

#import "Controller.h"
#import "ChatController.h"
#import "PlayerDataController.h"
#import "MobController.h"
#import "SpellController.h"
#import "NodeController.h"
#import "CombatController.h"
#import "MovementController.h"
#import "AuraController.h"
#import "WaypointController.h"
#import "ProcedureController.h"
#import "InventoryController.h"
#import "PlayersController.h"
#import "QuestController.h"
#import "CorpseController.h"
#import "LootController.h"
#import "ChatLogController.h"
#import "FishController.h"
#import "MacroController.h"
#import "OffsetController.h"
#import "MemoryViewController.h"
#import "CombatProfileEditor.h"
#import "EventController.h"
#import "BlacklistController.h"

#import "ChatLogEntry.h"
#import "BetterSegmentedControl.h"
#import "Behavior.h"
#import "RouteSet.h"
#import "Condition.h"
#import "Mob.h"
#import "Unit.h"
#import "Player.h"
#import "Item.h"
#import "Offsets.h"
#import "PTHeader.h"
#import "CGSPrivate.h"
#import "Macro.h"
#import "CombatProfileEditor.h"
#import "CombatProfile.h"
#import "Errors.h"

#import "ScanGridView.h"
#import "TransparentWindow.h"

#import <Growl/GrowlApplicationBridge.h>
#import <ShortcutRecorder/ShortcutRecorder.h>
#import <ScreenSaver/ScreenSaver.h>

#define DeserterSpellID         26013
#define HonorlessTargetSpellID  2479 
#define HonorlessTarget2SpellID 46705
#define IdleSpellID             43680
#define InactiveSpellID         43681
#define PreparationSpellID      44521
#define WaitingToRezSpellID     2584
#define HearthstoneItemID		6948
#define HearthStoneSpellID		8690

#define RefreshmentTableID		193061	// "Refreshment Table"
#define SoulwellID				193169	// "Soulwell"


// For strand of the ancients
#define StrandFlagpole					191311
#define StrandAllianceBanner			191310
#define StrandAllianceBannerAura		180100
#define StrandHordeBanner				191307
#define StrandeHordeBannerAura			180101
#define StrandAntipersonnelCannon		27894
#define StrandBattlegroundDemolisher	28781
#define StrandPrivateerZierhut			32658		// right boat
#define StrandPrivateerStonemantle		32657		// left boat

@interface BotController ()

@property (readwrite, retain) RouteSet *theRoute;
@property (readwrite, retain) Behavior *theBehavior;
@property (readwrite, retain) CombatProfile *theCombatProfile;
@property (readwrite, retain) NSDate *lootStartTime;
@property (readwrite, retain) NSDate *skinStartTime;
    
@property (readwrite, retain) NSDate *startDate;
@property (readwrite, retain) Mob *mobToSkin;
@property (readwrite, retain) WoWObject *unitToLoot;
@property (readwrite, retain) WoWObject *lastAttemptedUnitToLoot;
@property (readwrite, retain) Unit *preCombatUnit;

// pvp
@property (readwrite, assign) BOOL pvpPlayWarning;
@property (readwrite, assign) BOOL pvpLeaveInactive;
@property (readwrite, assign) int pvpCheckCount;

@property (readwrite, assign) BOOL doLooting;
@property (readwrite, assign) float gatherDistance;

@end

@interface BotController (Internal)

- (void)timeUp: (id)sender;
- (void)noAFK;

- (void)preRegen;
- (void)evaluateRegen: (NSDictionary*)regenDict;

- (BOOL)evaluateRule: (Rule*)rule withTarget: (Unit*)target asTest: (BOOL)test;
- (void)performProcedureWithState: (NSDictionary*)state;
- (void)playerHasDied: (NSNotification*)noti;

// pvp
- (void)pvpStop;
- (void)pvpStart;
- (void)pvpCheck;
- (void)pvpGetBGInfo;

- (void)rePop: (NSNumber *)count;
- (void)startBotForPvP;

- (void)skinMob: (Mob*)mob;
- (void)skinOrFinish;
- (BOOL)unitValidToHeal: (Unit*)unit;
- (void)lootNode: (WoWObject*) unit;

- (BOOL)mountNow;

- (BOOL)scaryUnitsNearNode: (WoWObject*)node doMob:(BOOL)doMobCheck doFriendy:(BOOL)doFriendlyCheck doHostile:(BOOL)doHostileCheck;

- (BOOL)combatProcedureValidForUnit: (Unit*)unit;

- (void)executeRegen: (BOOL)delay;

@end


@implementation BotController

+ (void)initialize {
    
    NSDictionary *defaultValues = [NSDictionary dictionaryWithObjectsAndKeys:
                                    [NSNumber numberWithBool: NO],      @"IgnoreRoute",
                                   [NSNumber numberWithBool: YES],      @"AttackAnyLevel",
                                   [NSNumber numberWithFloat: 50.0],    @"GatheringDistance",
                                   [NSNumber numberWithInt: NSOnState], @"PvPAddonAutoJoin",
                                   [NSNumber numberWithInt: NSOnState], @"PvPAddonAutoQueue",
                                   [NSNumber numberWithInt: NSOnState], @"PvPAddonAutoRelease",
                                   [NSNumber numberWithInt: NSOnState], @"PvPPlayWarningSound",
                                   [NSNumber numberWithInt: NSOnState], @"PvPLeaveWhenInactive",
								   [NSNumber numberWithInt:0],			@"MovementType",
								   [NSNumber numberWithInt: NSOffState],@"DoLogOutCheck",
								   [NSNumber numberWithInt:20],		    @"LogOutOnBrokenItemsPercentage",
								   [NSNumber numberWithBool:NO],		@"DisableReleasingOnDeath",
                                   nil];
    
    [[NSUserDefaults standardUserDefaults] registerDefaults: defaultValues];
    [[NSUserDefaultsController sharedUserDefaultsController] setInitialValues: defaultValues];
}

- (id) init
{
    self = [super init];
    if (self != nil) {
        [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(playerHasDied:) name: PlayerHasDiedNotification object: nil];
        [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(playerHasRevived:) name: PlayerHasRevivedNotification object: nil];
        [[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(playerIsInvalid:) 
                                                     name: PlayerIsInvalidNotification 
                                                   object: nil];

        [[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(auraGain:) 
                                                     name: BuffGainNotification 
                                                   object: nil];
        [[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(auraFade:) 
                                                     name: BuffFadeNotification 
                                                   object: nil];
		[[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(itemsLooted:) 
                                                     name: AllItemsLootedNotification 
                                                   object: nil];
		[[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(itemLooted:) 
                                                     name: ItemLootedNotification 
                                                   object: nil];
		[[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(whisperReceived:) 
                                                     name: WhisperReceived 
                                                   object: nil];
		[[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(eventZoneChanged:) 
                                                     name: EventZoneChanged 
                                                   object: nil];
		[[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(eventBattlegroundStatusChange:) 
                                                     name: EventBattlegroundStatusChange 
                                                   object: nil];
		[[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(unitDied:) 
                                                     name: UnitDiedNotification 
                                                   object: nil];
		[[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(playerEnteringCombat:) name: PlayerEnteringCombatNotification object: nil];
        [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(playerLeavingCombat:) name: PlayerLeavingCombatNotification object: nil];
		[[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(unitEnteredCombat:) name: UnitEnteredCombat object: nil];
		
        _procedureInProgress = nil;
		_lastProcedureExecuted = nil;
        _didPreCombatProcedure = NO;
		_doRegenProcedure = 0;
		_lastSpellCastGameTime = 0;
		self.startDate = nil;
		_unitToLoot = nil;
		_mobToSkin = nil;
		_shouldFollow = YES;
		_lastUnitAttemptedToHealed = nil;
		_pvpIsInBG = NO;
		self.lootStartTime = nil;
		self.skinStartTime = nil;
		_lootAttempt = 0;
		_lootMacroAttempt = 0;
		_zoneBeforeHearth = -1;
		_attackingInStrand = NO;
		_strandDelay = NO;
		_jumpAttempt = 0;
		_includeFriendly = NO;
		_lastSpellCast = 0;
        _mountAttempt = 0;
		_mountLastAttempt = nil;
		
        _mobsToLoot = [[NSMutableArray array] retain];
        
        // wipe pvp options
        self.isPvPing = NO;
        self.pvpLeaveInactive = NO;
        self.pvpPlayWarning = NO;
		
		// anti afk
		_lastPressedWasForward = NO;
		_afkTimerCounter = 0;
		
		// wg stuff
		_lastNumWGMarks = 0;
		_dateWGEnded = nil;
		
		_logOutTimer = nil;
		
		// Every 15 seconds we'll want to send clicks!
		_wgTimer = [NSTimer scheduledTimerWithTimeInterval: 15.0f target: self selector: @selector(wgTimer:) userInfo: nil repeats: YES];
		
		// Every 30 seconds for an anti-afk
		_afkTimer = [NSTimer scheduledTimerWithTimeInterval: 30.0f target: self selector: @selector(afkTimer:) userInfo: nil repeats: YES];
	
		
        [NSBundle loadNibNamed: @"Bot" owner: self];
    } 
    return self;
}

- (void)awakeFromNib {
    self.minSectionSize = [self.view frame].size;
    self.maxSectionSize = [self.view frame].size;
    
    [shortcutRecorder setCanCaptureGlobalHotKeys: YES];
    [startstopRecorder setCanCaptureGlobalHotKeys: YES];
    [petAttackRecorder setCanCaptureGlobalHotKeys: YES];
	[mouseOverRecorder setCanCaptureGlobalHotKeys: YES];
    
    KeyCombo combo1 = { NSShiftKeyMask, kSRKeysF13 };
    if([[NSUserDefaults standardUserDefaults] objectForKey: @"HotkeyCode"])
        combo1.code = [[[NSUserDefaults standardUserDefaults] objectForKey: @"HotkeyCode"] intValue];
    if([[NSUserDefaults standardUserDefaults] objectForKey: @"HotkeyFlags"])
        combo1.flags = [[[NSUserDefaults standardUserDefaults] objectForKey: @"HotkeyFlags"] intValue];

    KeyCombo combo2 = { NSCommandKeyMask, kSRKeysEscape };
    if([[NSUserDefaults standardUserDefaults] objectForKey: @"StartstopCode"])
        combo2.code = [[[NSUserDefaults standardUserDefaults] objectForKey: @"StartstopCode"] intValue];
    if([[NSUserDefaults standardUserDefaults] objectForKey: @"StartstopFlags"])
        combo2.flags = [[[NSUserDefaults standardUserDefaults] objectForKey: @"StartstopFlags"] intValue];
    
    KeyCombo combo3 = { NSShiftKeyMask, kVK_ANSI_T };
    if([[NSUserDefaults standardUserDefaults] objectForKey: @"PetAttackCode"])
        combo3.code = [[[NSUserDefaults standardUserDefaults] objectForKey: @"PetAttackCode"] intValue];
    if([[NSUserDefaults standardUserDefaults] objectForKey: @"PetAttackFlags"])
        combo3.flags = [[[NSUserDefaults standardUserDefaults] objectForKey: @"PetAttackFlags"] intValue];
        
    KeyCombo combo4 = { 0, -1 };
    if([[NSUserDefaults standardUserDefaults] objectForKey: @"MouseOverTargetCode"])
        combo4.code = [[[NSUserDefaults standardUserDefaults] objectForKey: @"MouseOverTargetCode"] intValue];
    if([[NSUserDefaults standardUserDefaults] objectForKey: @"MouseOverTargetFlags"])
        combo4.flags = [[[NSUserDefaults standardUserDefaults] objectForKey: @"MouseOverTargetFlags"] intValue];
	
    [shortcutRecorder setDelegate: nil];
    [startstopRecorder setDelegate: self];
    [petAttackRecorder setDelegate: nil];
	[mouseOverRecorder setDelegate: nil];

    [shortcutRecorder setKeyCombo: combo1];
    [startstopRecorder setKeyCombo: combo2];
    [petAttackRecorder setKeyCombo: combo3];
	[mouseOverRecorder setKeyCombo: combo4];
    
    [shortcutRecorder setDelegate: self];
    [petAttackRecorder setDelegate: self];
	[mouseOverRecorder setDelegate: self];
	
    // set up overlay window
    [overlayWindow setLevel: NSFloatingWindowLevel];
    if([overlayWindow respondsToSelector: @selector(setCollectionBehavior:)]) {
        [overlayWindow setCollectionBehavior: NSWindowCollectionBehaviorMoveToActiveSpace];
    }
    
    [self updateStatus: nil];
}

@synthesize theRoute;
@synthesize theBehavior;
@synthesize theCombatProfile;
@synthesize lootStartTime;
@synthesize skinStartTime;

@synthesize logOutAfterStuckCheckbox;
@synthesize view;
@synthesize isBotting = _isBotting;
@synthesize isPvPing = _isPvPing;
@synthesize procedureInProgress = _procedureInProgress;
@synthesize mobToSkin = _mobToSkin;
@synthesize unitToLoot = _unitToLoot;
@synthesize lastAttemptedUnitToLoot = _lastAttemptedUnitToLoot;
@synthesize minSectionSize;
@synthesize maxSectionSize;
@synthesize preCombatUnit;
@synthesize pvpPlayWarning = _pvpPlayWarning;
@synthesize pvpLeaveInactive = _pvpLeaveInactive;
@synthesize pvpCheckCount = _pvpCheckCount;

@synthesize startDate;
@synthesize doLooting       = _doLooting;
@synthesize gatherDistance  = _gatherDist;

- (NSString*)sectionTitle {
    return @"Start/Stop Bot";
}

- (CombatProfileEditor*)combatProfileEditor {
    return [CombatProfileEditor sharedEditor];
}

#pragma mark -

int DistanceFromPositionCompare(id <UnitPosition> unit1, id <UnitPosition> unit2, void *context) {
    
    //PlayerDataController *playerData = (PlayerDataController*)context; [playerData position];
    Position *position = (Position*)context; 

    float d1 = [position distanceToPosition: [unit1 position]];
    float d2 = [position distanceToPosition: [unit2 position]];
    if (d1 < d2)
        return NSOrderedAscending;
    else if (d1 > d2)
        return NSOrderedDescending;
    else
        return NSOrderedSame;
}


#pragma mark -

- (void)testRule: (Rule*)rule {
    Unit *unit = [mobController playerTarget];
    if(!unit) unit = [playersController playerTarget];

    PGLog(@"Testing rule with target: %@", unit);
    BOOL result = [self evaluateRule: rule withTarget: unit asTest: YES];
    NSRunAlertPanel(TRUE_FALSE(result), [NSString stringWithFormat: @"%@", rule], @"Okay", NULL, NULL);
}

- (BOOL)evaluateRule: (Rule*)rule withTarget: (Unit*)target asTest: (BOOL)test {
    //PGLog(@"Checking rule %@.", rule);
    //BOOL eval = [rule isMatchAll] ? YES : NO;

    int numMatched = 0, needToMatch = 0;
    if([rule isMatchAll]) {
        for(Condition *condition in [rule conditions]) {
            if( [condition enabled]) needToMatch++;
        }
    }
    if(needToMatch == 0) needToMatch = 1;
    
	Player *thePlayer = [playerController player];
	
	// target checks
	if ( [rule target] != TargetNone ){
		if ( ([rule target] == TargetFriend || [rule target] == TargetPet ) && ![playerController isFriendlyWithFaction: [target factionTemplate]] ){
			//PGLog(@"[Rule] Target isn't friendly! Bailing!");
			return NO;
		}
		
		if ( ([rule target] == TargetEnemy || [rule target] == TargetAdd) && [playerController isFriendlyWithFaction: [target factionTemplate]] ){
			//PGLog(@"[Rule] Target isn't an enemy! Bailing!");
			return NO;
		}
		
		// set the correct target if it's self
		if ( [rule target] == TargetSelf ){
			target = thePlayer;
		}
	}
	
	// check to see if the spell is on cooldown, obviously the rule will fail!
	if ( [[rule action] type] == ActionType_Spell ){
		if ( [spellController isSpellOnCooldown:[[rule action] actionID]] ){
			//PGLog(@"[Rule] Failed, spell is on cooldown!");
			return NO;
		}
	}
    
    for(Condition *condition in [rule conditions]) {
        //PGLog(@"Checking condition: %@", condition);
        
        if(![condition enabled]) continue;  // skip disabled conditions
        
        BOOL conditionEval = NO;
        if([condition unit] == UnitNone && [condition variety] != VarietySpellCooldown && [condition variety] != VarietyLastSpellCast ) goto loopEnd;
        if([condition unit] == UnitTarget && !target) goto loopEnd;
		if([condition unit] == UnitFriend && !target) goto loopEnd;
        
        switch([condition variety]) {
            case VarietyNone:;
                PGLog(@"Error: %@ in %@ is of an unknown type.", condition, rule);
                break;
            case VarietyHealth:;
                /* ******************************** */
                /* Health / Power Condition         */
                /* ******************************** */
                int qualityValue = 0;
                if( [condition unit] == UnitPlayer ) {
                    //PGLog(@"Checking player... type %d", [condition type]);
                    if( ![playerController playerIsValid:self] || ![thePlayer isValid]) goto loopEnd;
                    if( [condition quality] == QualityHealth ) {
                        qualityValue = ([condition type] == TypeValue) ? [thePlayer currentHealth] : [thePlayer percentHealth];
                    } else if ([condition quality] == QualityPower ) {
                        qualityValue = ([condition type] == TypeValue) ? [thePlayer currentPower] : [thePlayer percentPower];
                    } else if ([condition quality] == QualityMana ) {
                        qualityValue = ([condition type] == TypeValue) ? [thePlayer currentPowerOfType: UnitPower_Mana] : [thePlayer percentPowerOfType: UnitPower_Mana];
                    } else if ([condition quality] == QualityRage ) {
                        qualityValue = ([condition type] == TypeValue) ? [thePlayer currentPowerOfType: UnitPower_Rage] : [thePlayer percentPowerOfType: UnitPower_Rage];
                    } else if ([condition quality] == QualityEnergy ) {
                        qualityValue = ([condition type] == TypeValue) ? [thePlayer currentPowerOfType: UnitPower_Energy] : [thePlayer percentPowerOfType: UnitPower_Energy];
                    } else if ([condition quality] == QualityHappiness ) {
                        qualityValue = ([condition type] == TypeValue) ? [thePlayer currentPowerOfType: UnitPower_Happiness] : [thePlayer percentPowerOfType: UnitPower_Happiness];
                    } else if ([condition quality] == QualityFocus ) {
                        qualityValue = ([condition type] == TypeValue) ? [thePlayer currentPowerOfType: UnitPower_Focus] : [thePlayer percentPowerOfType: UnitPower_Focus];
                    } else if ([condition quality] == QualityRunicPower ) {
                        qualityValue = ([condition type] == TypeValue) ? [thePlayer currentPowerOfType: UnitPower_RunicPower] : [thePlayer percentPowerOfType: UnitPower_RunicPower];
                    } else goto loopEnd;
                } else {
                    // get unit as either target or player's pet or friend
                    Unit *aUnit = ([condition unit] == UnitTarget || [condition unit] == UnitFriend) ? target : [playerController pet];
                    if( ![aUnit isValid]) goto loopEnd;
                    if( [condition quality] == QualityHealth ) {
                        qualityValue = ([condition type] == TypeValue) ? [aUnit currentHealth] : [aUnit percentHealth];
                    } else if ([condition quality] == QualityPower ) {
                        qualityValue = ([condition type] == TypeValue) ? [aUnit currentPower] : [aUnit percentPower];
                    } else if ([condition quality] == QualityMana ) {
                        qualityValue = ([condition type] == TypeValue) ? [aUnit currentPowerOfType: UnitPower_Mana] : [aUnit percentPowerOfType: UnitPower_Mana];
                    } else if ([condition quality] == QualityRage ) {
                        qualityValue = ([condition type] == TypeValue) ? [aUnit currentPowerOfType: UnitPower_Rage] : [aUnit percentPowerOfType: UnitPower_Rage];
                    } else if ([condition quality] == QualityEnergy ) {
                        qualityValue = ([condition type] == TypeValue) ? [aUnit currentPowerOfType: UnitPower_Energy] : [aUnit percentPowerOfType: UnitPower_Energy];
                    } else if ([condition quality] == QualityHappiness ) {
                        qualityValue = ([condition type] == TypeValue) ? [aUnit currentPowerOfType: UnitPower_Happiness] : [aUnit percentPowerOfType: UnitPower_Happiness];
                    } else if ([condition quality] == QualityFocus ) {
                        qualityValue = ([condition type] == TypeValue) ? [aUnit currentPowerOfType: UnitPower_Focus] : [aUnit percentPowerOfType: UnitPower_Focus];
                    } else if ([condition quality] == QualityRunicPower ) {
                        qualityValue = ([condition type] == TypeValue) ? [aUnit currentPowerOfType: UnitPower_RunicPower] : [aUnit percentPowerOfType: UnitPower_RunicPower];
                    } else goto loopEnd;
                }
                
                // now we have the value of the quality
                if( [condition comparator] == CompareMore) {
                    conditionEval = ( qualityValue > [[condition value] unsignedIntValue] ) ? YES : NO;
                    //PGLog(@"  %d > %@ is %d", qualityValue, [condition value], conditionEval);
                } else if([condition comparator] == CompareEqual) {
                    conditionEval = ( qualityValue == [[condition value] unsignedIntValue] ) ? YES : NO;
                    //PGLog(@"  %d = %@ is %d", qualityValue, [condition value], conditionEval);
                } else if([condition comparator] == CompareLess) {
                    conditionEval = ( qualityValue < [[condition value] unsignedIntValue] ) ? YES : NO;
                    //PGLog(@"  %d > %@ is %d", qualityValue, [condition value], conditionEval);
                } else goto loopEnd;
                
                break;
                
                /* ******************************** */
                /* Status Condition                 */
                /* ******************************** */
            case VarietyStatus:; 
                //PGLog(@"-- Checking status condition --");
                
                // check alive status
                if( [condition state] == StateAlive ) {
                    if( [condition unit] == UnitPlayer)
                        conditionEval = ( [condition comparator] == CompareIs ) ? ![playerController isDead] : ![playerController isDead];
                    else if( [condition unit] == UnitTarget || [condition unit] == UnitFriend )
                        conditionEval = ( [condition comparator] == CompareIs ) ? ![target isDead] : [target isDead];
                    else if( [condition unit] == UnitPlayerPet) {
                        if(playerController.pet == nil) {
                            conditionEval = ([condition comparator] == CompareIs) ? NO : YES;
                        } else
                            conditionEval = ( [condition comparator] == CompareIs ) ? ![playerController.pet isDead] : [playerController.pet isDead];
                    } else goto loopEnd;
                    //PGLog(@"  Alive? %d", conditionEval);
                }
                
                // check combat status
                if( [condition state] == StateCombat ) {
                    if( [condition unit] == UnitPlayer)
                        conditionEval = ( [condition comparator] == CompareIs ) ? [combatController inCombat] : ![combatController inCombat];
                    else if( [condition unit] == UnitTarget || [condition unit] == UnitFriend )
                        conditionEval = ( [condition comparator] == CompareIs ) ? [target isInCombat] : ![target isInCombat];
                    else if( [condition unit] == UnitPlayerPet)
                        conditionEval = ( [condition comparator] == CompareIs ) ? [playerController.pet isInCombat] : ![playerController.pet isInCombat];
                    else goto loopEnd;
                    //PGLog(@"  Combat? %d", conditionEval);
                }
                
                // check casting status
                if( [condition state] == StateCasting ) {
                    if( [condition unit] == UnitPlayer)
                        conditionEval = ( [condition comparator] == CompareIs ) ? [playerController isCasting] : ![playerController isCasting];
                    else if( [condition unit] == UnitTarget || [condition unit] == UnitFriend )
                        conditionEval = ( [condition comparator] == CompareIs ) ? [target isCasting] : ![target isCasting];
                    else if( [condition unit] == UnitPlayerPet)
                        conditionEval = ( [condition comparator] == CompareIs ) ? [playerController.pet isCasting] : ![playerController.pet isCasting];
                    goto loopEnd;
                    //PGLog(@"  Casting? %d", conditionEval);
                }
                
                // IS THE UNIT MOUNTED?
                if( [condition state] == StateMounted ) {
                    if(test) PGLog(@"Doing State IsMounted condition...");
                    Unit *aUnit = nil;
                    if( [condition unit] == UnitPlayer)         aUnit = thePlayer;
                    else if( [condition unit] == UnitTarget || [condition unit] == UnitFriend )    aUnit = target;
                    else if( [condition unit] == UnitPlayerPet) aUnit = playerController.pet;
                    if(test) PGLog(@" --> Testing unit %@", aUnit);
                    
                    if([aUnit isValid]) {
                        conditionEval = ( [condition comparator] == CompareIs ) ? [aUnit isMounted] : ![aUnit isMounted];
                        if(test) PGLog(@" --> Unit is mounted? %@", YES_NO(conditionEval));
                    } else {
                        if(test) PGLog(@" --> Unit is invalid.");
                    }
                }
                
                // IS THE PLAYER INDOORS?
                if( [condition state] == StateIndoors ) {
                    if(test) PGLog(@"Doing State 'Indoors' condition...");
                    conditionEval = ( [condition comparator] == CompareIs ) ? [playerController isIndoors] : [playerController isOutdoors];
                    if(test) {
                        if([condition comparator] == CompareIs) {
                            if(conditionEval)   PGLog(@" --> (%@) Unit is indoors.", TRUE_FALSE(conditionEval));
                            else                PGLog(@" --> (%@) Unit is not indoors.", TRUE_FALSE(conditionEval));
                        } else {
                            if(conditionEval)   PGLog(@" --> (%@) Unit is not indoors.", TRUE_FALSE(conditionEval));
                            else                PGLog(@" --> (%@) Unit is indoors.", TRUE_FALSE(conditionEval));
                        }
                    }
                }
                
                break;
                
                /* ******************************** */
                /* Aura Condition                   */
                /* ******************************** */
            case VarietyAura:;
                //PGLog(@"-- Checking aura condition --");
                
                unsigned spellID = 0;
                NSString *dispelType = nil;
                BOOL doDispelCheck = ([condition quality] == QualityBuffType) || ([condition quality] == QualityDebuffType);
                
                // sanity checks
                if(!doDispelCheck) {
                    if( [condition type] == TypeValue)
                        spellID = [[condition value] unsignedIntValue];
                    
                    if( ([condition type] == TypeValue) && !spellID) {
                        // invalid spell ID
                        goto loopEnd;
                    } else if( [condition type] == TypeString && (![condition value] || ![[condition value] length])) {
                        // invalid spell name
                        goto loopEnd;
                    }
                } else {
                    if( ([condition state] < StateMagic) || ([condition state] > StatePoison)) {
                        // invalid dispel type
                        goto loopEnd;
                    } else {
                        if([condition state] == StateMagic)     dispelType = DispelTypeMagic;
                        if([condition state] == StateCurse)     dispelType = DispelTypeCurse;
                        if([condition state] == StatePoison)    dispelType = DispelTypePoison;
                        if([condition state] == StateDisease)   dispelType = DispelTypeDisease;
                    }
                }
                
                //PGLog(@"  Searching for spell '%@'", [condition value]);
                
                Unit *aUnit = nil;
                if( [condition unit] == UnitPlayer ) {
                    if( ![playerController playerIsValid:self]) goto loopEnd;
                    aUnit = thePlayer;
                } else {
                    aUnit = ([condition unit] == UnitTarget || [condition unit] == UnitFriend) ? target : [playerController pet];
                }
                
                if( [aUnit isValid]) {
                    if( [condition quality] == QualityBuff ) {
                        if([condition type] == TypeValue)
                            conditionEval = ([condition comparator] == CompareExists) ? [auraController unit: aUnit hasBuff: spellID] : ![auraController unit: aUnit hasBuff: spellID];
                        if([condition type] == TypeString)
                            conditionEval = ([condition comparator] == CompareExists) ? [auraController unit: aUnit hasBuffNamed: [condition value]] : ![auraController unit: aUnit hasBuffNamed: [condition value]];
                    } else if([condition quality] == QualityDebuff) {
                        if([condition type] == TypeValue)
                            conditionEval = ([condition comparator] == CompareExists) ? [auraController unit: aUnit hasDebuff: spellID] : ![auraController unit: aUnit hasDebuff: spellID];
                        if([condition type] == TypeString)
                            conditionEval = ([condition comparator] == CompareExists) ? [auraController unit: aUnit hasDebuffNamed: [condition value]] : ![auraController unit: aUnit hasDebuffNamed: [condition value]];
                    } else if([condition quality] == QualityBuffType) {
                        conditionEval = ([condition comparator] == CompareExists) ? [auraController unit: aUnit hasBuffType: dispelType] : ![auraController unit: aUnit hasBuffType: dispelType];
                    } else if([condition quality] == QualityDebuffType) {
                        conditionEval = ([condition comparator] == CompareExists) ? [auraController unit: aUnit hasDebuffType: dispelType] : ![auraController unit: aUnit hasDebuffType: dispelType];
                    }
                } else goto loopEnd;
                
                break;
                
                
                /* ******************************** */
                /* Aura Stack Condition             */
                /* ******************************** */
            case VarietyAuraStack:;
                
                spellID = 0;
                dispelType = nil;
                
                if(test) PGLog(@"Doing Aura Stack condition...");
                
                // sanity checks
                if(([condition type] != TypeValue) && ([condition type] != TypeString)) {
                    if(test) PGLog(@" --> Invalid condition type.");
                    goto loopEnd;
                }
                if( [condition type] == TypeValue) {
                    spellID = [[condition value] unsignedIntValue];
                    if(spellID == 0) { // invalid spell ID
                        if(test) PGLog(@" --> Invalid spell number");
                        goto loopEnd;
                    } else {
                        if(test) PGLog(@" --> Scanning for aura %u", spellID);
                    }
                }
                if( [condition type] == TypeString) {
                    if( ![[condition value] isKindOfClass: [NSString class]] || ![[condition value] length] ) {
                        if(test) PGLog(@" --> Invalid or blank Spell name.");
                        goto loopEnd;
                    } else {
                        if(test) PGLog(@" --> Scanning for aura \"%@\"", [condition value]);
                    }
                }
                
                aUnit = nil;
                if( [condition unit] == UnitPlayer ) {
                    if( ![playerController playerIsValid:self]) goto loopEnd;
                    aUnit = thePlayer;
                } else {
                    aUnit = ([condition unit] == UnitTarget || [condition unit] == UnitFriend) ? target : [playerController pet];
                }
                
                if( [aUnit isValid]) {
                    //PGLog(@"Testing unit %@ for %d", aUnit, spellID);
                    int stackCount = 0;
                    if( [condition quality] == QualityBuff ) {
                        if([condition type] == TypeValue)   stackCount = [auraController unit: aUnit hasBuff: spellID];
                        if([condition type] == TypeString)  stackCount = [auraController unit: aUnit hasBuffNamed: [condition value]];
                    } else if([condition quality] == QualityDebuff) {
                        if([condition type] == TypeValue)   stackCount = [auraController unit: aUnit hasDebuff: spellID];
                        if([condition type] == TypeString)  stackCount = [auraController unit: aUnit hasDebuffNamed: [condition value]];
                    }
                    
                    if([condition comparator] == CompareMore) {
                        conditionEval = (stackCount > [condition state]);
                    }
                    if([condition comparator] == CompareEqual) {
                        conditionEval = (stackCount == [condition state]);
                    }
                    if([condition comparator] == CompareLess) {
                        conditionEval = (stackCount < [condition state]);
                    }
                    if(test) PGLog(@" --> Found %d stacks for result %@", stackCount, (conditionEval ? @"TRUE" : @"FALSE"));
                    // conditionEval = ([condition comparator] == CompareMore) ? (stackCount > [condition state]) : (([condition comparator] == CompareEqual) ? (stackCount == [condition state]) : (stackCount < [condition state]));
                } else goto loopEnd;
                
                break;
                
                
                /* ******************************** */
                /* Distance Condition               */
                /* ******************************** */
            case VarietyDistance:;
                
                if( [condition unit] == UnitTarget && [condition quality] == QualityDistance && target) {
                    float distanceToTarget = [[(PlayerDataController*)playerController position] distanceToPosition: [target position]];
                    //PGLog(@"-- Checking distance condition --");
                    
                    if( [condition comparator] == CompareMore) {
                        conditionEval = ( distanceToTarget > [[condition value] floatValue] ) ? YES : NO;
                        //PGLog(@"  %f > %@ is %d", distanceToTarget, [condition value], conditionEval);
                    } else if([condition comparator] == CompareEqual) {
                        conditionEval = ( distanceToTarget == [[condition value] floatValue] ) ? YES : NO;
                        //PGLog(@"  %f = %@ is %d", distanceToTarget, [condition value], conditionEval);
                    } else if([condition comparator] == CompareLess) {
                        conditionEval = ( distanceToTarget < [[condition value] floatValue] ) ? YES : NO;
                        //PGLog(@"  %f < %@ is %d", distanceToTarget, [condition value], conditionEval);
                    } else goto loopEnd;
                }
                
                break;
                
                
                /* ******************************** */
                /* Inventory Condition              */
                /* ******************************** */
            case VarietyInventory:;
                if( [condition unit] == UnitPlayer && [condition quality] == QualityInventory) {
                    //PGLog(@"-- Checking inventory condition --");
                    Item *item = ([condition type] == TypeValue) ? [itemController itemForID: [condition value]] : [itemController itemForName: [condition value]];
                    
                    int totalCount = [itemController collectiveCountForItemInBags: item];
                    if( [condition comparator] == CompareMore) {
                        conditionEval = (totalCount > [condition state]) ? YES : NO;
                    }
                    
                    if( [condition comparator] == CompareEqual) {
                        conditionEval = (totalCount == [condition state]) ? YES : NO;
                    }
                    
                    if( [condition comparator] == CompareLess) {
                        conditionEval = (totalCount < [condition state]) ? YES : NO;
                    }
                }
                break;
                
                /* ******************************** */
                /* Combo Points Condition           */
                /* ******************************** */
            case VarietyComboPoints:;
                
                if(test) PGLog(@"Doing Combo Points condition...");
                
                UInt32 class = [thePlayer unitClass];
				
                if( (class != UnitClass_Rogue) && (class != UnitClass_Druid) ) {
                    if(test) PGLog(@" --> You are not a rogue or druid, noob.");
                    goto loopEnd;
                }
                
                if( ([condition unit] == UnitPlayer) && ([condition quality] == QualityComboPoints) && target) {
                    
                    // either we have no CP target, or our CP target matched our current target
                    UInt64 cpUID = [playerController comboPointUID];
                    if( (cpUID == 0) || ([target GUID] == cpUID)) {
                        int comboPoints = [playerController comboPoints];
                        if(test) PGLog(@" --> Found %d combo points.", comboPoints);
                        
                        if( [condition comparator] == CompareMore) {
                            conditionEval = ( comboPoints > [[condition value] intValue] ) ? YES : NO;
                            if(test) PGLog(@" --> %d > %@ is %@.", comboPoints, [condition value], TRUE_FALSE(conditionEval));
                        } else if([condition comparator] == CompareEqual) {
                            conditionEval = ( comboPoints == [[condition value] intValue] ) ? YES : NO;
                            if(test) PGLog(@" --> %d = %@ is %@.", comboPoints, [condition value], TRUE_FALSE(conditionEval));
                        } else if([condition comparator] == CompareLess) {
                            conditionEval = ( comboPoints < [[condition value] intValue] ) ? YES : NO;
                            if(test) PGLog(@" --> %d < %@ is %@.", comboPoints, [condition value], TRUE_FALSE(conditionEval));
                        } else goto loopEnd;
                    }
                }
                
                break;
                
                /* ******************************** */
                /* Totem Condition                  */
                /* ******************************** */
            case VarietyTotem:;
                
                if(test) PGLog(@"Doing Totem condition...");
                
                if( ![condition value] || ![[condition value] length] || ![[condition value] isKindOfClass: [NSString class]] ) {
                    if(test) PGLog(@" --> Invalid totem name.");
                    goto loopEnd;
                }
                if( ([condition unit] != UnitPlayer) || ([condition quality] != QualityTotem)) {
                    if(test) PGLog(@" --> Invalid condition parameters.");
                    goto loopEnd;
                }
                if( [thePlayer unitClass] != UnitClass_Shaman ) {
                    if(test) PGLog(@" --> You are not a shaman, noob.");
                    goto loopEnd;
                }
                
                // we need to rescan the mob list before we check for active totems
                // [mobController enumerateAllMobs];
                
                BOOL foundTotem = NO;
                for(Mob* mob in [mobController allMobs]) {
                    if( [mob isTotem] && ([mob createdBy] == [playerController GUID]) ) {
                        NSRange range = [[mob name] rangeOfString: [condition value]
                                                          options: NSCaseInsensitiveSearch | NSAnchoredSearch | NSDiacriticInsensitiveSearch];
                        if(range.location != NSNotFound) {
                            foundTotem = YES;
                            if(test) PGLog(@" --> Found totem %@ matching \"%@\".", mob, [condition value]);
                            break;
                        }
                    }
                }
                
                if(!foundTotem && test) {
                    PGLog(@" --> No totem found with name \"%@\"", [condition value]);
                }
                
                conditionEval = ([condition comparator] == CompareExists) ? foundTotem : !foundTotem;
                
                break;
                
                
                /* ******************************** */
                /* Temp. Enchant Condition          */
                /* ******************************** */
            case VarietyTempEnchant:;
                
                if(test) PGLog(@"Doing Temp Enchant condition...");
                
                Item *item = [itemController itemForGUID: [thePlayer itemGUIDinSlot: ([condition quality] == QualityMainhand) ? SLOT_MAIN_HAND : SLOT_OFF_HAND]];
                if(test) PGLog(@" --> Got item %@.", item);
                BOOL hadEnchant = [item hasTempEnchantment];
                conditionEval = ([condition comparator] == CompareExists) ? hadEnchant : !hadEnchant;
                if(test) PGLog(@" --> Had enchant? %@. Result is %@.", YES_NO(hadEnchant), TRUE_FALSE(conditionEval));
				
                break;
                
                
                /* ******************************** */
                /* Target Type Condition          */
                /* ******************************** */
            case VarietyTargetType:;
                
                if(test) PGLog(@"Doing Target Type condition...");
                
                if([condition quality] == QualityNPC) {
                    conditionEval = [target isNPC];
                    if(test) PGLog(@" --> Is NPC? %@", YES_NO(conditionEval));
                }
                if([condition quality] == QualityPlayer) {
                    conditionEval = [target isPlayer];
                    if(test) PGLog(@" --> Is Player? %@", YES_NO(conditionEval));
                }
                break;
                
                /* ******************************** */
                /* Target Class Condition           */
                /* ******************************** */
            case VarietyTargetClass:;
                
                if(test) PGLog(@"Doing Target Class condition...");
                
                if([condition quality] == QualityNPC) {
                    conditionEval = ([target creatureType] == [condition state]);
                    if(test) PGLog(@" --> Unit Creature Type %d == %d? %@", [condition state], [target creatureType], YES_NO(conditionEval));
                }
                if([condition quality] == QualityPlayer) {
                    conditionEval = ([target unitClass] == [condition state]);
                    if(test) PGLog(@" --> Unit Class %d == %d? %@", [condition state], [target unitClass], YES_NO(conditionEval));
                }
                break;
                
                
                /* ******************************** */
                /* Combat Count Condition           */
                /* ******************************** */
            case VarietyCombatCount:;
                
                if(test) PGLog(@"Doing Combat Count condition...");
                
                int unitsAttackingMe = [[combatController combatList] count];
                if(test) PGLog(@" --> Found %d units attacking me.", unitsAttackingMe);
                
                if( [condition comparator] == CompareMore) {
                    conditionEval = ( unitsAttackingMe > [condition state] ) ? YES : NO;
                    if(test) PGLog(@" --> %d > %d is %@.", unitsAttackingMe, [condition state], TRUE_FALSE(conditionEval));
                } else if([condition comparator] == CompareEqual) {
                    conditionEval = ( unitsAttackingMe == [condition state] ) ? YES : NO;
                    if(test) PGLog(@" --> %d = %d is %@.", unitsAttackingMe, [condition state], TRUE_FALSE(conditionEval));
                } else if([condition comparator] == CompareLess) {
                    conditionEval = ( unitsAttackingMe < [condition state] ) ? YES : NO;
                    if(test) PGLog(@" --> %d < %d is %@.", unitsAttackingMe, [condition state], TRUE_FALSE(conditionEval));
                } else goto loopEnd;
                break;
                
                
                /* ******************************** */
                /* Proximity Count Condition        */
                /* ******************************** */
            case VarietyProximityCount:;
                if(test) PGLog(@"Doing Proximity Count condition...");

                float distance = [[condition value] floatValue];
				
				// get list of all possible targets
				NSArray *allTargets = [combatController enemiesWithinRange:distance];
				int inRangeCount = [allTargets count];

                if(test) PGLog(@" --> Found %d total units.", [allTargets count]);
                
                // compare with specified number of units
                if( [condition comparator] == CompareMore) {
                    conditionEval = ( inRangeCount > [condition state] ) ? YES : NO;
                    if(test) PGLog(@" --> %d > %d is %@.", inRangeCount, [condition state], TRUE_FALSE(conditionEval));
                } else if([condition comparator] == CompareEqual) {
                    conditionEval = ( inRangeCount == [condition state] ) ? YES : NO;
                    if(test) PGLog(@" --> %d = %d is %@.", inRangeCount, [condition state], TRUE_FALSE(conditionEval));
                } else if([condition comparator] == CompareLess) {
                    conditionEval = ( inRangeCount < [condition state] ) ? YES : NO;
                    if(test) PGLog(@" --> %d < %d is %@.", inRangeCount, [condition state], TRUE_FALSE(conditionEval));
                } else goto loopEnd;
                
                break;
				
				/* ******************************** */
                /* Spell Cooldown Condition        */
                /* ******************************** */
            case VarietySpellCooldown:;
                if(test) PGLog(@"Doing Spell Cooldown condition...");
				
				BOOL onCD = NO;
				
				// checking by spell ID
				if ( [condition type] == TypeValue ){
					
					unsigned spellID = [[condition value] unsignedIntValue];
					if ( !spellID )
						goto loopEnd;
					
					// check
					onCD = [spellController isSpellOnCooldown:spellID];
					conditionEval = ( [condition comparator] == CompareIs ) ? onCD : !onCD;
					if(test) PGLog(@" Spell %d is (not? %d) on cooldown? %d", spellID, [condition comparator] == CompareIsNot, onCD);
				}
				
				// checking by spell ID
				else if ( [condition type] == TypeString ){
					
					// sanity check
					if ( ![condition value] || ![[condition value] length] )
						goto loopEnd;
					
					Spell *spell = [spellController spellForName:[condition value]];
					if ( spell && [spell ID] ){
						onCD = [spellController isSpellOnCooldown:[[spell ID] unsignedIntValue]];
						conditionEval = ( [condition comparator] == CompareIs ) ? onCD : !onCD;
						if(test) PGLog(@" Spell %@ is (not? %d) on cooldown? %d", spell, [condition comparator] == CompareIsNot, conditionEval);
					}
				}
				
				break;
				
				/* ******************************** */
                /* Last Spell Cast Condition        */
                /* ******************************** */
            case VarietyLastSpellCast:;
                if(test) PGLog(@"Doing Last Spell Cast condition...");
				
				// checking by spell ID
				if ( [condition type] == TypeValue ){
					
					unsigned spellID = [[condition value] unsignedIntValue];
					if ( !spellID )
						goto loopEnd;
					
					// check
					BOOL spellCast = (_lastSpellCast == spellID);
					conditionEval = ( [condition comparator] == CompareIs ) ? spellCast : !spellCast;
					if(test) PGLog(@" Spell %d %d was%@ the last spell cast? %d", spellID, _lastSpellCast, (([condition comparator] == CompareIs ) ? @"" : @" not"), conditionEval);
				}
				
				// checking by spell ID
				else if ( [condition type] == TypeString ){
					
					// sanity check
					if ( ![condition value] || ![[condition value] length] )
						goto loopEnd;
					
					Spell *spell = [spellController spellForName:[condition value]];
					if ( spell && [spell ID] ){
						BOOL spellCast = (_lastSpellCast == [[spell ID] unsignedIntValue]);
						conditionEval = ( [condition comparator] == CompareIs ) ? spellCast : !spellCast;
						if(test) PGLog(@" Spell %d %d was%@ the last spell cast? %d", [[spell ID] unsignedIntValue], _lastSpellCast, (([condition comparator] == CompareIs ) ? @"" : @" not"), conditionEval);
					}
				}
				
				break;
				
				/* ******************************** */
                /* Rune Condition        */
                /* ******************************** */
            case VarietyRune:;
                if(test) PGLog(@"Doing Rune condition...");
				
				// get our rune type
				int runeType = RuneType_Blood;
				if ( [condition quality] == QualityRuneUnholy )
					runeType = RuneType_Unholy;
				else if ( [condition quality] == QualityRuneFrost )
					runeType = RuneType_Frost;
				else if ( [condition quality] == QualityRuneDeath )
					runeType = RuneType_Death;
				
				// quality value
				int runesAvailable = [playerController runesAvailable:runeType];
				
				// now we have the value of the quality
                if( [condition comparator] == CompareMore) {
                    conditionEval = ( runesAvailable > [[condition value] unsignedIntValue] ) ? YES : NO;
                    //PGLog(@"  %d > %@ is %d", runesAvailable, [condition value], conditionEval);
                } else if([condition comparator] == CompareEqual) {
                    conditionEval = ( runesAvailable == [[condition value] unsignedIntValue] ) ? YES : NO;
                    //PGLog(@"  %d = %@ is %d", runesAvailable, [condition value], conditionEval);
                } else if([condition comparator] == CompareLess) {
                    conditionEval = ( runesAvailable < [[condition value] unsignedIntValue] ) ? YES : NO;
                    //PGLog(@"  %d > %@ is %d", runesAvailable, [condition value], conditionEval);
                } else goto loopEnd;
	
				
				if(test) PGLog(@" Checking type %d - is %d equal to %@", runeType, [playerController runesAvailable:runeType], [condition value]);
				
				break;
				
            default:;
                break;
        }
        
    loopEnd:
        if(conditionEval)   {
            numMatched++;
            //if(test) NSRunAlertPanel(@"Condition True", [NSString stringWithFormat: @"%@ is true.", condition], @"Okay", NULL, NULL);
        } else {
            //if(test) NSRunAlertPanel(@"Condition False", [NSString stringWithFormat: @"%@ is false.", condition], @"Okay", NULL, NULL);
        }
        
        // shortcut bail if we can
        if([rule isMatchAll]) {
            if(!conditionEval) return NO;
        } else {
            if(conditionEval) return YES;
        }
    }
    
    // match all requires as many Yes and there are conditions
    //if([rule isMatchAll] && (numMatched >= needToMatch ))
    //    return YES;
    //if(![rule isMatchAll] && (numMatched > 0))
    //    return YES;
    //PGLog(@"    Matched %d of %d", numMatched, needToMatch);

    if(numMatched >= needToMatch)
        return YES;
    return NO;
}

#define RULE_EVAL_DELAY_SHORT   0.25f
#define RULE_EVAL_DELAY_NORMAL  0.5f
#define RULE_EVAL_DELAY_LONG    0.5f

- (void)cancelCurrentProcedure {
    [NSObject cancelPreviousPerformRequestsWithTarget: self];
	[_lastProcedureExecuted release]; _lastProcedureExecuted = nil;
	if ( self.procedureInProgress )
		_lastProcedureExecuted = [NSString stringWithString:self.procedureInProgress];
    [self setProcedureInProgress: nil];
}

- (void)finishCurrentProcedure: (NSDictionary*)state {
	
	PGLog(@"[Bot] Finishing Procedure: %@", [state objectForKey: @"Procedure"]);
    
    // make sure we're done casting before we end the procedure
    if( [playerController isCasting] ) {
        float timeLeft = [playerController castTimeRemaining];
        if( timeLeft <= 0 ) {
            [self performSelector: _cmd withObject: state afterDelay: 0.1];
        } else {
            // PGLog(@"[Bot] Still casting (%.2f remains): Delaying procedure end.", timeLeft);
            [self performSelector: _cmd withObject: state afterDelay: timeLeft];
            return;
        }
        return;
    }
    
    //if( ![[state objectForKey: @"Procedure"] isEqualToString: CombatProcedure])
    // PGLog(@"--- All done with procedure: %@.", [state objectForKey: @"Procedure"]);
    [self cancelCurrentProcedure];
    
    // when we finish PreCombat, re-evaluate the situation
    if([[state objectForKey: @"Procedure"] isEqualToString: PreCombatProcedure]) {
		PGLog(@"[Eval] After PreCombat");
        [self evaluateSituation];
        return;
    }
    
	
    // when we finish PostCombat, run regen
    if([[state objectForKey: @"Procedure"] isEqualToString: PostCombatProcedure]) {
		
		if ( [playerController isInCombat] ){
			PGLog(@"[Procedure] Still in combat, waiting for regen!");
			_doRegenProcedure = 1;
			PGLog(@"[Eval] Start Regen");
			[self evaluateSituation];
		}
		else{
			PGLog(@"[Procedure] Not in combat, running regen..");
			[self executeRegen: ([[state objectForKey: @"ActionsPerformed"] intValue] > 0)];
		}
        return;
    }
    
    // if we did any regen, wait 30 seconds before re-evaluating the situation
    if([[state objectForKey: @"Procedure"] isEqualToString: RegenProcedure]) {
        if( [[state objectForKey: @"ActionsPerformed"] intValue] > 0 ) {
			PGLog(@"[Procedure] Starting regen!");
            [self performSelector: @selector(monitorRegen:) withObject: [[NSDate date] retain] afterDelay: 2.0];
        } else {
            // or if we didn't regen, go back to evaluate
			PGLog(@"[Eval] No regen");
            [self evaluateSituation];
        }
    }
	
	// after PostCombat, lets evaluate
	if([[state objectForKey: @"Procedure"] isEqualToString: PostCombatProcedure]) {
		PGLog(@"[Eval] After PostCombat");
        [self evaluateSituation];
    }
	
    
    // if we did the Patrolling procdure, go back to evaluate
    if([[state objectForKey: @"Procedure"] isEqualToString: PatrollingProcedure]) {
        [self evaluateSituation];
    }
	
	if([[state objectForKey: @"Procedure"] isEqualToString: CombatProcedure]) {
		
        PGLog(@"[Bot] Combat completed, moving to PostCombat (in combat? %d)", [playerController isInCombat]);
		
		[self performSelector: @selector(performProcedureWithState:) 
				   withObject: [NSDictionary dictionaryWithObjectsAndKeys: 
								PostCombatProcedure,              @"Procedure",
								[NSNumber numberWithInt: 0],      @"CompletedRules", nil] 
				   afterDelay: (0.1)];
    }
}

- (void)performProcedureWithState: (NSDictionary*)state {
	
    // if there's another procedure running, we gotta stop it
    if( self.procedureInProgress && ![self.procedureInProgress isEqualToString: [state objectForKey: @"Procedure"]]) {
        [self cancelCurrentProcedure];
        PGLog(@"Cancelling a previous procedure to begin %@.", [state objectForKey: @"Procedure"]);
    }
	
	// reset
	_doRegenProcedure = 0;
	
    if(![self procedureInProgress]) {
        [self setProcedureInProgress: [state objectForKey: @"Procedure"]];
        PGLog(@"Setting current procedure: %@", self.procedureInProgress);
        
        if ( ![[self procedureInProgress] isEqualToString: CombatProcedure] ){
            if( [[self procedureInProgress] isEqualToString: PreCombatProcedure])
                [controller setCurrentStatus: @"Bot: Pre-Combat Phase"];
            else if( [[self procedureInProgress] isEqualToString: PostCombatProcedure])
                [controller setCurrentStatus: @"Bot: Post-Combat Phase"];
            else if( [[self procedureInProgress] isEqualToString: RegenProcedure])
                [controller setCurrentStatus: @"Bot: Regen Phase"];
        }
    }
	
	if ( [[self procedureInProgress] isEqualToString: CombatProcedure]) {
		NSArray *combatList = [combatController combatList];
		
		int count =		[combatList count];
		if(count == 1)  [controller setCurrentStatus: [NSString stringWithFormat: @"Bot: Player in Combat (%d unit)", count]];
		else            [controller setCurrentStatus: [NSString stringWithFormat: @"Bot: Player in Combat (%d units)", count]];
	}
    
    Procedure *procedure = [self.theBehavior procedureForKey: [state objectForKey: @"Procedure"]];
    Unit *target = [state objectForKey: @"Target"];
	Unit *originalTarget = target;
    int completed = [[state objectForKey: @"CompletedRules"] intValue];
    int attempts = [[state objectForKey: @"RuleAttempts"] intValue];
    int actions = [[state objectForKey: @"ActionsPerformed"] intValue];
	NSMutableDictionary *rulesTried = [state objectForKey: @"RulesTried"];
	if ( rulesTried == nil ){
		//PGLog(@"[Procedure^^^^^^^^^^^^^] Creating dictionary to track our tried rules!");
		rulesTried = [[NSMutableDictionary dictionary] retain];
	}
    
    // have we completed all the rules?
    int ruleCount = [procedure ruleCount];
    if( !procedure /*|| completed >= ( ruleCount * 2 )*/ ) {
        [self finishCurrentProcedure: state];
        return;
    }
    
    // delay our next rule until we can cast
    if( [playerController isCasting] ) {
        // try to be smart about how long we wait
        float delayTime = [playerController castTimeRemaining]/2.0f;
        if(delayTime < RULE_EVAL_DELAY_LONG) delayTime = RULE_EVAL_DELAY_LONG;
        PGLog(@"  Player casting. Waiting %.2f to perform next rule.", delayTime);
        
        [self performSelector: _cmd
                   withObject: state 
                   afterDelay: delayTime];
        return;
    }
	
	// We don't want to cast if our GCD is active!
	if ( [spellController isGCDActive] ){
		[self performSelector: _cmd
                   withObject: state 
                   afterDelay: RULE_EVAL_DELAY_SHORT];
		return;
	}
    
    // have we exceeded our maximum attempts on this rule?
    if(attempts > 3) {
        PGLog(@"  Exceeded maximum (3) attempts on action %d (%@). Skipping.", [[procedure ruleAtIndex: completed] actionID], [[spellController spellForID:[NSNumber numberWithInt:[[procedure ruleAtIndex: completed] actionID]]] name]);
        [self performSelector: _cmd
                   withObject: [NSDictionary dictionaryWithObjectsAndKeys: 
                                [state objectForKey: @"Procedure"],             @"Procedure",
                                [NSNumber numberWithInt: completed+1],          @"CompletedRules",
                                target,                                         @"Target",  nil] 
                   afterDelay: RULE_EVAL_DELAY_SHORT];
        return;
    }
	
	Rule *rule = nil;
	int i = 0;
	BOOL matchFound = NO;
	// priority system for combat
	if ( [[self procedureInProgress] isEqualToString: CombatProcedure]) {
		
		// kind of a hack right now, but it *should* work
		//	I'm running into a problem where PG will not loot after death, but instead move onto a hostile NOT in combat
		//	So lets add a check here, this isn't how I want it to operate, but it will work for now
		BOOL doCombatProcedure = YES;
		if ( self.doLooting && [_mobsToLoot count] ){
			NSArray *inCombatUnits = [combatController validUnitsWithFriendly:_includeFriendly onlyHostilesInCombat:YES];
			
			// we can break out of this procedure early!
			if ( [inCombatUnits count] == 0 ){
				doCombatProcedure = NO;
				PGLog(@"[Procedure] Not executing combat procedure!");
			}
			else{
				PGLog(@"[Procedure] Executing combat procedure. %d units remain", [inCombatUnits count]);
			}
		}
		
		// temp fix for looting
		if ( doCombatProcedure ){
			NSArray *units = [combatController validUnitsWithFriendly:_includeFriendly onlyHostilesInCombat:NO];
			NSArray *adds = [combatController allAdds];
			for ( i = 0; i < ruleCount; i++ ) {
				rule = [procedure ruleAtIndex: i];
				
				PGLog(@"[Procedure] Evaluating rule %@", rule);
				
				// make sure our rule hasn't continuously failed!
				NSString *triedRuleKey = [NSString stringWithFormat:@"%d_0x%qX", i, [target GUID]];
				NSNumber *tries = [rulesTried objectForKey:triedRuleKey];
				if ( tries ){
					if ( [tries intValue] > 3 ){
						PGLog(@"[Procedure^^^^^^^^^^^^^] Rule %d failed after %@ attempts!", i, tries);
						continue;
					}
				}
				
				// then set the target to ourself
				if ( [rule target] == TargetSelf ){
					target = [playerController player];
					
					if ( [self evaluateRule: rule withTarget: target asTest: NO] ){
						// do something
						PGLog(@"[Procedure] Match for %@ with target %@", rule, target);
						matchFound = YES;
						
					}
				}
				
				// no target
				else if ( [rule target] == TargetNone ){
					if ( [self evaluateRule: rule withTarget: target asTest: NO] ){
						// do something
						PGLog(@"[Procedure] Match for %@", rule);
						matchFound = YES;
					}
				}
				
				// add
				else if ( [rule target] == TargetAdd ){
					
					// only check for an add if we don't have one already!
					if ( [combatController addUnit] == nil ){
						for ( target in adds ){
							if ( [self evaluateRule: rule withTarget: target asTest: NO] ){
								// do something
								PGLog(@"[Procedure] Match for %@ with add %@", rule, target);
								matchFound = YES;
								break;
							}
						}
					}
				}
				
				// pet
				else if ( [rule target] == TargetPet ){
					target = [playerController pet];
					
					if ( [self evaluateRule: rule withTarget: target asTest: NO] ){
						// do something
						PGLog(@"[Procedure] Pet match for %@", rule);
						matchFound = YES;
					}
				}
				
				// TO DO: we need pet in here?
				
				// loop through all units
				else{
					
					//Unit *notInCombatUnit = nil;
					for ( target in units ){
						
						// special rule if we're NOT pvping
						if ( !self.isPvPing ){
							// if we're in combat, and the unit is not, ignore!
							if ( [playerController isInCombat] && ![target isInCombat] ){
								PGLog(@"[Procedure] Ignoring %@ since we're in combat and the target isn't!", target);
								
								// special condition (helps hunters!)
								/*if ( notInCombatUnit == nil && [self evaluateRule: rule withTarget: target asTest: NO] ){
									notInCombatUnit = target;
								}*/
								
								continue;
							}
						}
						
						if ( [self evaluateRule: rule withTarget: target asTest: NO] ){
							// do something
							PGLog(@"[Procedure] Match for %@ with unit %@", rule, target);
							PGLog(@"  Player in combat: %d  Unit in combat: %d", [playerController isInCombat], [target isInCombat]);
							matchFound = YES;
							break;
						}
					}
					
					// "special condition"
					/*if ( !matchFound && notInCombatUnit ){
						PGLog(@"[Bot] No match found, but %@ isn't in combat, using!", notInCombatUnit);
						target = notInCombatUnit;
					}*/
				}
				
				if ( matchFound ){
					break;
				}
			}
		}
	}
	// old-school for non-combat (just goes in order)
	else {
		
		PGLog(@"[Procedure] Starting search at rule %d", completed);
		for ( i = completed; i < ruleCount; i++) {
			rule = [procedure ruleAtIndex: i];
			
			if( [self evaluateRule: rule withTarget: target asTest: NO] ) {
				PGLog(@"[Procedure] Found match for non-combat with rule %@", rule);
				matchFound = YES;
				break;
			}
		}
		
		completed = i;
	}
		
	// take the action here
	if ( matchFound && rule ){
		
		PGLog(@"[Procedure] Act on target %@ with rule %@", target, rule );

		// target if needed!
		if ( [[self procedureInProgress] isEqualToString: CombatProcedure]) {
			[combatController stayWithUnit:target withType:[rule target]];
		}
		
		// send in pet if needed
		if ( [self.theBehavior usePet] && [playerController pet] && ![[playerController pet] isDead] && [rule target] == TargetEnemy ) {
			if ( [[self procedureInProgress] isEqualToString: PreCombatProcedure] || [[self procedureInProgress] isEqualToString: CombatProcedure] ) {
				if ( ![controller isWoWChatBoxOpen] && (_currentPetAttackHotkey >= 0 ) ) {
					PGLog(@"[Bot] Sending in pet to attack!");
					[chatController pressHotkey: _currentPetAttackHotkey withModifier: _currentPetAttackHotkeyModifier];
				}
			}
		}
		
		if ( [rule resultType] > 0 ){
			
			int32_t actionID = [rule actionID];
			
			if ( actionID > 0 ) {
				BOOL canPerformAction = YES;
				// if we are using an item or macro, apply a mask to the item number
				switch([rule resultType]) {
					case ActionType_Item: 
						actionID = (USE_ITEM_MASK + actionID);
						break;
					case ActionType_Macro:
						actionID = (USE_MACRO_MASK + actionID);
						break;
					case ActionType_Spell:
						canPerformAction = ![spellController isSpellOnCooldown: actionID];
						break;
					default:
						break;
				}
				
				// lets do the action
				if ( canPerformAction ){
					
					// target yourself
					if ( [rule target] == TargetSelf ){
						PGLog(@"[Procedure] Targeting self");
						[playerController setPrimaryTarget: [playerController player]];
					}
					else if ( [rule target] != TargetNone ){
						[playerController setPrimaryTarget: target];
					}
					
					// Let the target change set in (generally this shouldn't be needed, but I've noticed sometimes the target doesn't switch)
					usleep([controller refreshDelay]);
					
					// do it!
					int actionResult = [self performAction:actionID];
					PGLog(@"[Procedure] Action %d taken with result: %d", actionID, actionResult);
					
					// error of some kind :/
					if ( actionResult != ErrNone ){
						PGLog(@"[Procedure] Attempted to take action on %@ %d %d times", target, attempts, completed);
						
						if ( originalTarget == target ){
							PGLog(@"[Procedure] Same target!");
						}
						
						NSString *triedRuleKey = [NSString stringWithFormat:@"%d_0x%qX", i, [target GUID]];
						PGLog(@"[Procedure^^^^^^^^^^^^^] Looking for key %@", triedRuleKey);
						
						NSNumber *tries = [rulesTried objectForKey:triedRuleKey];
						
						if ( tries ){
							int t = [tries intValue];
							tries = [NSNumber numberWithInt:t+1];
						}
						else{
							tries = [NSNumber numberWithInt:1];
						}
						
						PGLog(@"[Procedure^^^^^^^^^^^^^] Setting tried %@ with value %@", triedRuleKey, tries);

						[rulesTried setObject:tries forKey:triedRuleKey];
					}
					// success!
					else{
						actions++;
						completed++;
					}
				}
				else{
					PGLog(@"[Procedure] Unable to perform action");
				}
			}
			else{
				PGLog(@"[Procedure] No action to take");
			}
		}
		else{
			PGLog(@"[Procedure] No result type");
		}
		
		// if we found a match, try again until we can't anymore!
		[self performSelector: _cmd
				   withObject: [NSDictionary dictionaryWithObjectsAndKeys: 
								[state objectForKey: @"Procedure"],				@"Procedure",
								[NSNumber numberWithInt: completed],            @"CompletedRules",
								[NSNumber numberWithInt: actions],				@"ActionsPerformed",        // but increment attempts
								[NSNumber numberWithInt: attempts+1],			@"RuleAttempts",			// but increment attempts
								rulesTried,										@"RulesTried",				// track how many times we've tried each rule
								target,											@"Target", nil]
				   afterDelay: 0.1f];
		PGLog(@"[Procedure] Rule executed, trying for more rules!");
		return;
	}

	// we're done
	PGLog(@"[Procedure] Done! Finishing!");
	[self finishCurrentProcedure: state];
}

#pragma mark -
#pragma mark Loot Helpers

- (void)lootNode: (WoWObject*) unit{
	
	// Loot if we're on the ground!
	if ( [playerController isOnGround] ){
		PGLog(@"[Loot] Player on ground, looting %@", unit);
		[self performSelector: @selector(lootUnit:) withObject: unit afterDelay:0.5f];	
	}
	
	// Try again shortly
	else {
		// macro failed for me once, so adding this here just in case
		if ( [[playerController player] isMounted] )
			[movementController dismount];
		
		PGLog(@"[Loot] Player sill in air, waiting to reach the ground");
		
		[self performSelector: @selector(lootNode:) withObject: unit afterDelay:0.1f];	
	}
	
	// We should do a check to see if the player is casting after an attempted loot! if they're not we could keep trying!??
}


- (void)lootUnit: (WoWObject*) unit{
    BOOL isNode = [unit isKindOfClass: [Node class]];
	
    if ( self.doLooting || isNode ) {
        Position *playerPosition = [playerController position];
        float distanceToUnit = [playerController isOnGround] ? [playerPosition distanceToPosition2D: [unit position]] : [playerPosition distanceToPosition: [unit position]];
		[movementController pauseMovement];
        [movementController turnTowardObject: unit];
		
		self.lastAttemptedUnitToLoot = unit;
		
        if([unit isValid] && (distanceToUnit <= 5.0)) { //  && (unitIsMob ? [(Mob*)unit isLootable] : YES)
            
			[controller setCurrentStatus: @"Bot: Looting"];
			PGLog(@"[Loot] Looting : %@", unit);
			
			self.lootStartTime = [NSDate date];
			self.unitToLoot = unit;
			self.mobToSkin = (Mob*)unit;
			_lootAttempt++;
			
			// Lets do this instead of the loot hotkey!
			[self interactWithMouseoverGUID: [unit GUID]];
			
			// In the off chance that no items are actually looted
			[self performSelector: @selector(verifyLootSuccess) withObject: nil afterDelay: (isNode) ? 6.5f : 2.5f];
        } 
		else {
			PGLog(@"[Bot] Unit not within 5 yards (%d) or is invalid (%d), unable to loot - removing %@ from list", [unit isValid], distanceToUnit <= 5.0, unit );
			
			// This will ensure we won't try to loot this node again - /cry
			if ( [self.unitToLoot isKindOfClass: [Node class]] ){
				//[nodeController finishedNode: (Node*)self.unitToLoot];
			}
			else{
				[_mobsToLoot removeObject: self.unitToLoot];
			}
			
			// Not 100% sure why we need this, but it seems important?
			[NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(reachedUnit:) object: self.unitToLoot];
			
			PGLog(@"[Eval] lootUnit");
			[self performSelector: @selector(evaluateSituation) withObject: nil afterDelay: 0.1f];	
        }
    }
}

// Sometimes there isn't an item to loot!  So we'll use this to fire off the notification
- (void)verifyLootSuccess{
	
	// Check if the player is casting still (herbalism/mining/skinning)
	if ( [playerController isCasting] ){
		[self performSelector: @selector(verifyLootSuccess) withObject: nil afterDelay: 1.0f];
		
		return;
	}
	
	// Is the loot window stuck being open?
	if ( [lootController isLootWindowOpen] && _lootMacroAttempt < 3 ){
		PGLog(@"[Loot] Loot window open? ZOMG lets close it!");
		
		_lootMacroAttempt++;
		
		[lootController acceptLoot];
		[self performSelector: @selector(verifyLootSuccess) withObject: nil afterDelay: 1.0f];
		
		return;
	}
	else if ( _lootMacroAttempt >= 3 ){
		PGLog(@"[Loot] Attempted to loot %d times, moving on...", _lootMacroAttempt);
	}
	
	// fire off notification (sometimes needed if the mob only had $$, or the loot failed)
	if ( self.unitToLoot ){
		
		PGLog(@"[Loot] Firing off loot success");
		
		// is it a mob?
		if ( [self.mobToSkin isKindOfClass: [Mob class]] && [self.mobToSkin isNPC] ){
			PGLog(@"[Loot] Is mob still lootable? %d", [(Mob*)self.unitToLoot isLootable] );
		}
		
		[[NSNotificationCenter defaultCenter] postNotificationName: AllItemsLootedNotification object: [NSNumber numberWithInt:0]];	
	}
}

// This is called when all items have actually been looted (the loot window will NOT be open at this point)
- (void)itemsLooted: (NSNotification*)notification {
	
	if ( !self.isBotting )
		return;
	
	// If this event fired, we don't need to verifyLootSuccess! We ONLY need verifyLootSuccess when a body has nothing to loot!
	[NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(verifyLootSuccess) object: nil];
	
	// This lets us know that the LAST loot was just from us looting a corpse (vs. via skinning or herbalism)
	if ( self.unitToLoot ){
		NSDate *currentTime = [NSDate date];
		
		// Unit was looted, remove from list!
		if ( [self.unitToLoot isKindOfClass: [Node class]] ){
			//[nodeController finishedNode: (Node*)self.unitToLoot];
			self.mobToSkin = nil;
			PGLog(@"[Loot] Node looted in %0.2f seconds after %d attempt%@", [currentTime timeIntervalSinceDate: self.lootStartTime], _lootAttempt, _lootAttempt == 1 ? @"" : @"s");
		}
		else{
			[_mobsToLoot removeObject: self.unitToLoot];
			PGLog(@"[Loot] Mob looted in %0.2f seconds after %d attempt%@. %d mobs to loot remain", [currentTime timeIntervalSinceDate: self.lootStartTime], _lootAttempt, _lootAttempt == 1 ? @"" : @"s", [_mobsToLoot count]);
		}

		// Not 100% sure why we need this, but it seems important?
		[NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(reachedUnit:) object: self.unitToLoot];
	}
	// Here from skinning!
	else if ( self.mobToSkin ){
		NSDate *currentTime = [NSDate date];
		PGLog(@"[Loot] Skinning completed in %0.2f seconds", [currentTime timeIntervalSinceDate: self.skinStartTime]);
		
		self.mobToSkin = nil;
	}
	
	// Lets skin the mob, or we're done!
	[self skinOrFinish];
	
	// No longer need this unit!
	self.unitToLoot = nil;
}

// called when ONE item is looted
- (void)itemLooted: (NSNotification*)notification {
	
	PGLog(@"[Loot] Looted %@", [notification object]);
	
	// should we try to use the item?
	if ( _lootUseItems ){
		
		PGLog(@"[Loot] Check enabled...");
		
		int itemID = [[notification object] intValue];
		
		// crystallized <air|earth|fire|shadow|life|water> or mote of <air|earth|fire|life|mana|shadow|water>
		if ( ( itemID >= 37700 && itemID <= 37705 ) || ( itemID >= 22572 && itemID <= 22578 ) ){
			PGLog(@"[Loot] Useable item looted, checking to see if we have > 10 of %d", itemID);
			
			Item *item = [itemController itemForID:[notification object]];
			if ( item ){
				int collectiveCount = [itemController collectiveCountForItem:item];
				
				if ( collectiveCount >= 10 ){
					
					PGLog(@"[Loot] We have more than 10 of %@, using!", item);
					
					[self performAction:itemID + USE_ITEM_MASK];					
				}				
			}
		}
	}
}

- (void)skinOrFinish{
	
	if ( [fishController isFishing] )
		return;
	
	BOOL canSkin = NO;
	BOOL unitIsMob = ([self.mobToSkin isKindOfClass: [Mob class]] && [self.mobToSkin isNPC]);
	
	// Should we be skinning?
	if ( ( _doSkinning || _doHerbalism ) && self.mobToSkin && unitIsMob ){
		
		// Up to skinning 100, you can find out the highest level mob you can skin by: ((Skinning skill)/10)+10.
		// From skinning level 100 and up the formula is simply: (Skinning skill)/5.
		int canSkinUpToLevel = 0;
		if(_skinLevel <= 100) {
			canSkinUpToLevel = (_skinLevel/10)+10;
		} else {
			canSkinUpToLevel = (_skinLevel/5);
		}
		
		if ( _doSkinning || _doHerbalism ) {
			if ( canSkinUpToLevel >= [self.mobToSkin level] ) {
				
				_skinAttempt = 0;
				
				[self skinMob:self.mobToSkin];
				
				canSkin = YES;
			} 
			else {
				PGLog(@"[Loot] The mob is above your max %@ level (%d).", ((_doSkinning) ? @"skinning" : @"herbalism"), canSkinUpToLevel);
			}
		}
	}
	
	// We're done looting+skinning!
	if ( !canSkin ){
		NSDate *currentTime = [NSDate date];
		PGLog(@"[Loot] All looting completed in %0.2f seconds", [currentTime timeIntervalSinceDate: self.lootStartTime]);
		
		// Reset our attempt variables!
		_lootAttempt = 0;
		_lootMacroAttempt = 0;
		self.lastAttemptedUnitToLoot = nil;
		
		// Mount?  Or just evaluate
		PGLog(@"[Eval] After skinned");
		[self performSelector: @selector(evaluateSituation) withObject: nil afterDelay: (([self mountNow]) ? 2.0f : 0.1f)];
	}
}

// It actually takes 1.2 - 2.0 seconds for [mob isSkinnable] to change to the correct status, this makes me very sad as a human, seconds wasted!
- (void)skinMob: (Mob*)mob {
    float distanceToUnit = [[playerController position] distanceToPosition2D: [mob position]];
	 
	// We tried for 2.0 seconds, lets bail
	if ( _skinAttempt++ > 20 ){
		PGLog(@"[Skinning] Mob is not valid (%d), not skinnable (%d) or is too far away (%d)", ![mob isValid], ![mob isSkinnable], distanceToUnit > 5.0f );
		self.mobToSkin = nil;
		//[movementController finishMovingToObject: (Unit*)mob];
		
		PGLog(@"[Eval] Unable to skin");
		[self performSelector: @selector(evaluateSituation) withObject: nil afterDelay: 0.1];
		
		return;
	}
	
	// Set to null so our loot notifier realizes we shouldn't try to skin again :P
	self.mobToSkin = nil;
	self.skinStartTime = [NSDate date];
	
	// Not able to skin :/
	if( ![mob isValid] || ![mob isSkinnable] || distanceToUnit > 5.0f ) {
		
		[self performSelector: @selector(skinMob:) withObject:mob afterDelay:0.1f];
        return;
    } 
	
	[controller setCurrentStatus: @"Bot: Skinning"];
	
	PGLog(@"[Loot] Skinning!");
	
	// Lets interact w/the mob!
	[self interactWithMouseoverGUID: [mob GUID]];
	
	// In the off chance that no items are actually looted
	//[self performSelector: @selector(verifyLootSuccess) withObject: nil afterDelay: (isNode) ? 6.5f : 2.5f];
}

#pragma mark -
#pragma mark [Input] CombatController

- (void)unitEnteredCombat: (NSNotification*)notification {
	if(![self isBotting]) return;
	
	Unit *unit = [notification object];
	
	PGLog(@"[Bot] Unit %@ entered combat!", unit);
	
	// start a combat procedure if we're not in one!
	if ( ![self.procedureInProgress isEqualToString: CombatProcedure] ){
		
		// make sure we're not flying
		if ( self.theCombatProfile.ignoreFlying && ![playerController isOnGround] ){
			PGLog(@"[Bot] Ignoring combat with %@ since we're flying!", unit);
			return;
		}
		
		PGLog(@"[Bot] Acting on the above unit!");
		[self actOnUnit:unit];
	}
	else{
		PGLog(@"[Bot] Already in combat procedure! Not acting on unit");
	}
}

- (void)playerEnteringCombat: (NSNotification*)notification {
	if(![self isBotting]) return;
	
    [controller setCurrentStatus: @"Bot: Player in Combat"];
	
	// should we evaluate?
	PGLog(@"[Eval] Entering combat in BOT");
	[self evaluateSituation];
}

- (void)playerLeavingCombat: (NSNotification*)notification {
	
	if(![self isBotting]) return;
	
	_didPreCombatProcedure = NO;
	
	if ( [playerController isDead] ){
		return;
	}
	
	/*PGLog(@"[Bot] Left combat, current procedure: %@", self.procedureInProgress);
	[self evaluateSituation];
	
	if ( self.procedureInProgress && ![self.procedureInProgress isEqualToString: CombatProcedure]) {*/
		// start post-combat after specified delay
	
	// This is an odd situation that can occur (still in CombatProcedure when we leave combat)
	//	But basically it comes from killing something, then while we're casting on another we leave combat
	//	To prevent weird shit, lets not move to PostCombat if we're in combat!
	PGLog(@"[Bot] Left combat! Current procedure: %@  Last executed: %@", self.procedureInProgress, _lastProcedureExecuted);
	
	//if(self.theRoute) [movementController pauseMovement];
	[movementController resetUnit];
	
	PGLog(@"[Bot] should we evaluate after resetting the unit?");

}

#pragma mark Combat


// should we include friendly units?
- (BOOL)includeFriendlyInCombat{
	
	if ( self.theCombatProfile.healingEnabled ){
		return YES;
	}
	
	// lets loop through for some friendly rules
	Procedure *procedure = [self.theBehavior procedureForKey: CombatProcedure];
    int i;
    for ( i = 0; i < [procedure ruleCount]; i++ ) {
        Rule *rule = [procedure ruleAtIndex: i];
		
		if ( [rule target] == TargetFriend ){
			return YES;
		}
	}
	
	return NO;	
}

- (BOOL)combatProcedureValidForUnit: (Unit*)unit{
	
	Procedure *procedure = [self.theBehavior procedureForKey: CombatProcedure];
    
    int ruleCount = [procedure ruleCount];
    if( !procedure || ruleCount == 0 ) {
        return NO;
    }

	Rule *rule = nil;
	int i;
	BOOL matchFound = NO;
	for ( i = 0; i < ruleCount; i++ ) {
		rule = [procedure ruleAtIndex: i];
		
		//PGLog(@"[ValidProcedure] Evaluating rule %@ for %@", rule, unit);
		
		if ( [self evaluateRule: rule withTarget: unit asTest: NO] ){
			matchFound = YES;
			break;
		}
	}
	
	return matchFound;
}

// this function will actually fire off our combat procedure if needed! 
- (void)actOnUnit: (Unit*)unit {
	if ( ![self isBotting] )	return;
	
	// in theory we should never be here
	if ( [blacklistController isBlacklisted:unit] ){
		PGLog(@"Attempting to attack a blacklisted unit, ruh-roh");
	}
	
	
	PGLog(@"[Bot] Acting on unit %@", unit);
	
    if( ![[self procedureInProgress] isEqualToString: CombatProcedure] ) {

		BOOL readyToAttack = NO;
        
        // check to see if we are supposed to be in melee range
        if ( self.theBehavior.meleeCombat) {
			float distance = [[playerController position] distanceToPosition2D: [unit position]];
			
			// not in range, continue moving!
			if ( distance > 5.0f ){
				PGLog(@"[Bot] Still %0.2f away, moving to %@", distance, unit);
				
				[movementController moveToObject:unit andNotify:YES];
			}
			// we're in range
			else{
				PGLog(@"[Bot] In range, attacking! (should we pause here? don't think it's needed)");
				readyToAttack = YES;
				//[movementController pauseMovement];
			}

        } else {
			PGLog(@"[Bot] Don't need to be in melee, pausing movement!");
            // if we don't need to be in melee, pause
            [movementController pauseMovement];
			readyToAttack = YES;
        }
		
		PGLog(@"[Bot] Starting combat procedure (current: %@) for target %@", [self procedureInProgress], unit);
		
		// cancel current procedure
		[self cancelCurrentProcedure];
		
		// start the combat procedure
		[self performProcedureWithState: [NSDictionary dictionaryWithObjectsAndKeys: 
										  CombatProcedure,                  @"Procedure",
										  [NSNumber numberWithInt: 0],      @"CompletedRules",
										  unit,                             @"Target", nil]];
    } else {
		PGLog(@"[Bot] Not acting on unit, are we stuck doing nothing?  Current procedure: %@", [self procedureInProgress]);
    }
}

// this is called when any unit enters combat
- (void)addingUnit: (Unit*)unit {
    if(![self isBotting]) return;
    
    //if( ![[self procedureInProgress] isEqualToString: CombatProcedure] && [unit isValid] ) {
    //    PGLog(@"[Bot] Add! Stopping current procedure to attack.", unit);
    //    [self cancelCurrentProcedure];
    //}
    
    float vertOffset = [[[[NSUserDefaultsController sharedUserDefaultsController] values] valueForKey: @"CombatBlacklistVerticalOffset"] floatValue];
    if(self.isPvPing && ([[playerController position] verticalDistanceToPosition: [unit position]] > vertOffset)) {
        PGLog(@"[Bot] Added mob is beyond vertical offset limit; ignoring.");
        return;
    }
	
	// Don't attack if the player is mounted and in the air!
	if ( ![playerController isOnGround] && [[playerController player] isMounted] ){
		return;
	}
    
    //PGLog(@"[Bot] Adding %@", unit);
    
    if( [controller sendGrowlNotifications] && [GrowlApplicationBridge isGrowlInstalled] && [GrowlApplicationBridge isGrowlRunning]) {
        NSString *unitName = ([unit name]) ? [unit name] : nil;
        // [GrowlApplicationBridge setGrowlDelegate: @""];
        [GrowlApplicationBridge notifyWithTitle: [NSString stringWithFormat: @"%@ Entering Combat", [unit isPlayer] ? @"Player" : @"Mob"]
                                    description: ( unitName ? [NSString stringWithFormat: @"[%d] %@ at %d%%", [unit level], unitName, [unit percentHealth]] : ([unit isPlayer]) ? [NSString stringWithFormat: @"[%d] %@ %@, %d%%", [unit level], [Unit stringForRace: [unit race]], [Unit stringForClass: [unit unitClass]], [unit percentHealth]] : [NSString stringWithFormat: @"[%d] %@, %d%%", [unit level], [Unit stringForClass: [unit unitClass]], [unit percentHealth]])
                               notificationName: @"AddingUnit"
                                       iconData: [[unit iconForClass: [unit unitClass]] TIFFRepresentation]
                                       priority: 0
                                       isSticky: NO
                                   clickContext: nil];             
    }
    
    //[combatController disposeOfUnit: unit];
}

- (void)unitDied: (NSNotification*)notification{
	Unit *unit = [notification object];
	
	PGLog(@"[Bot] Unit %@ killed %@", unit, [unit class]);
	
	// unit dead, reset!
	[movementController resetUnit];
	
	if ( [unit isNPC] ){
		PGLog(@"[Bot] Flags: %d %d", [(Mob*)unit isTappedByMe], [(Mob*)unit isLootable] );
	}
	
	if ( self.doLooting && [unit isNPC] ) {
		// make sure this mob is even lootable
		// sometimes the mob isn't marked as 'lootable' yet because it hasn't fully died (death animation or whatever)
		usleep(500000);
		
		if ( [(Mob*)unit isTappedByMe] || [(Mob*)unit isLootable] ) {
			
			// mob already in our list? in theory this should never happen (how could we kill a unit twice? lul)
			if ([_mobsToLoot containsObject: unit]) {
				PGLog(@"[Loot] %@ was already in the loot list, removing first", unit);
				[_mobsToLoot removeObject: unit];
			}
			
			PGLog(@"[Loot] Adding %@ to loot list.", unit);
			[_mobsToLoot addObject: (Mob*)unit];
		}
		else{
			PGLog(@"[Loot] Mob %@ isn't lootable, ignoring", unit);
		}
	}
	
	// if we're in the middle of a combat procedure, end it
	/*if([[self procedureInProgress] isEqualToString: CombatProcedure])
		[self cancelCurrentProcedure];*/
}

/*
- (void)finishUnit: (Unit*)unit {
	
	

    // we only need to loot this if it's a mob and if was one we were directed to attack
    if( [unit isNPC] ) {
        if(wasInQueue) {
            if([movementController moveToObject] == unit) {
                // PGLog(@"finishUnit says stop moving to this unit.");
                [movementController finishMovingToObject: unit];
            }
            
            if([unit isDead]) {
                if(self.doLooting) {
                    // make sure this mob is even lootable
                    // sometimes the mob isn't marked as 'lootable' yet because it hasn't fully died (death animation or whatever)
                    usleep(500000);
                    if([(Mob*)unit isTappedByMe] || [(Mob*)unit isLootable]) {
                        if ([_mobsToLoot containsObject: unit]) {
                            PGLog(@"[Loot] %@ was already in the loot list, removing first", unit);
                            [_mobsToLoot removeObject: unit];
                        }
                        PGLog(@"[Loot] Adding %@ to loot list.", unit);
                        [_mobsToLoot addObject: (Mob*)unit];
                    }
					else{
						PGLog(@"[Loot] Mob %@ isn't lootable, ignoring", unit);
					}
                }
            }
			else{
				PGLog(@"[Loot] Unit %@ finished, but not dead! Health: %d", unit, [unit currentHealth]);
			}
            
            // if we're in the middle of a combat procedure, end it
            if([[self procedureInProgress] isEqualToString: CombatProcedure])
                [self cancelCurrentProcedure];
        }
        return;
    }
    
    if( [unit isPlayer] ) {
        [self evaluateSituation];
    }
    
}*/

/*
- (void)lootNodeWhenOnGround: (WoWObject*)unit{
	
	PGLog(@"[Bot] Movement flags 0x%x %d", [playerController movementFlags], [playerController movementFlags] & 0x0);
	
	// Is our player on the ground?
	if ( ( [playerController movementFlags] & 0x0 ) == 0x0 ){
		[self lootUnit: unit];
		return;
	}
	
	// Wait for fall time!
	[self performSelector: @selector(lootNodeWhenOnGround:) withObject: unit afterDelay:0.1f];
}*/

#pragma mark -
#pragma mark [Input] MovementController

- (void)reachedUnit: (WoWObject*)unit {
	
	PGLog(@"[Bot] Reached unit! %@", unit);
    
    [NSObject cancelPreviousPerformRequestsWithTarget: self selector: _cmd object: unit];
    [movementController pauseMovement];
	
	// no longer moving toward unit
	[movementController resetUnit];
	
    // if it's a player, or a non-dead NPC, we must be doing melee combat
    if( [unit isPlayer] || ([unit isNPC] && ![(Unit*)unit isDead])) {
        PGLog(@"[Bot] Reached melee range with %@", unit);
        return;
    }
	
	// If it's a node, we'll need to dismount (in case we are flying) - then we need to have a delay (for fall time)
	if ( [unit isKindOfClass: [Node class]] && [[playerController player] isMounted] ){
		
		// In case we didn't stop? Sometimes this happens, it makes me a sad panda
		[movementController pauseMovement];
		
		Position *playerPosition = [playerController position];
		float distance = [playerPosition distanceToPosition: [unit position]];
		float distance2D = [playerPosition distanceToPosition2D: [unit position]];
		float vertDist = [playerPosition verticalDistanceToPosition:[unit position]];

		
		PGLog(@"[Bot] 3D:%0.2f   2D:%0.2f   Vertical:%0.2f", distance, distance2D, vertDist);
		
		// Get off our mount (this could be called if our movement failed, we don't want to get off our mount!)!
		if ( distance <= NODE_DISTANCE_UNTIL_DISMOUNT){
			[movementController dismount];
			[self lootNode: unit];
		}
		else{
			// This node is "done" - this is a sort of blacklist, we just don't want it anymore!
			//[nodeController finishedNode: (Node*)self.unitToLoot];
			
			// Resume movement!
			[movementController resumeMovementToNearestWaypoint];
		}
		

		//[self performSelector: @selector(lootUnit:) withObject: unit afterDelay:2.5f];
	}
	else{
		[self lootUnit: unit];
	}
}

- (void)finishedRoute: (Route*)route {
    if( ![self isBotting]) return;
    
    if(self.theRoute) {
        if(route == [self.theRoute routeForKey: CorpseRunRoute]) {
            PGLog(@"Finished Corpse Run. Begin search for body...");
            [controller setCurrentStatus: @"Bot: Searching for body..."];
            [movementController setPatrolRoute: [self.theRoute routeForKey: PrimaryRoute]];
            [movementController beginPatrol: 1 andAttack: NO];
        } else {
            //PGLog(@"Finished something else...");
        }
	}
}

- (BOOL)shouldProceedFromWaypoint: (Waypoint*)waypoint {
    if( ![self isBotting]) return YES;
    if( [playerController isDead]) return YES;
    
    // see if we would be performing anything in the patrol procedure
    BOOL performPatrolProc = NO;
    for(Rule* rule in [[self.theBehavior procedureForKey: PatrollingProcedure] rules]) {
        if( ([rule resultType] != ActionType_None) && ([rule actionID] > 0) && [self evaluateRule: rule withTarget: nil asTest: NO] ) {
            performPatrolProc = YES;
            break;
        }
    }
    
    // check if all used abilities are instant
    BOOL needToPause = NO;
    for(Rule* rule in [[self.theBehavior procedureForKey: PatrollingProcedure] rules]) {

        if( ([rule resultType] == ActionType_Spell)) {
            Spell *spell = [spellController spellForID: [NSNumber numberWithUnsignedInt: [rule actionID]]];
            if([spell isInstant]) {
                continue;
            }
        }
        
        if([rule resultType] == ActionType_None) continue;
        
        needToPause = YES; 
        break;
    }
    
    // if we are, pause movement and perform it.
    if(performPatrolProc) {
        //if(needToPause)  PGLog(@"[Bot] Pausing to perform Patrol Procedure.");
        //if(!needToPause) PGLog(@"[Bot] NOT pausing to perform Patrol Procedure.");
        
        // only pause if we are performing something non instant
        if(needToPause) [movementController pauseMovement];

        [self performSelector: @selector(performProcedureWithState:) 
                   withObject: [NSDictionary dictionaryWithObjectsAndKeys: 
                                PatrollingProcedure,              @"Procedure",
                                [NSNumber numberWithInt: 0],      @"CompletedRules", nil] 
                   afterDelay: (needToPause ? 0.25 : 0.0)];
        
        if(needToPause)  return NO;
    }
    return YES;
}

#pragma mark -

- (void)executeRegen: (BOOL)delay{
	
	float regenDelay = 0.0f;
	if( delay ) {
		regenDelay = 1.5f;
	}
	
	[self performSelector: @selector(performProcedureWithState:) 
			   withObject: [NSDictionary dictionaryWithObjectsAndKeys: 
							RegenProcedure,                   @"Procedure",
							[NSNumber numberWithInt: 0],      @"CompletedRules", nil] 
			   afterDelay: regenDelay];
}


- (void)monitorRegen: (NSDate*)start{
	
	if ( [playerController isInCombat] ){
		PGLog(@"[Eval] monitorRegen");
		[self evaluateSituation];
		return;
	}
	
	Unit *player = [playerController player];
	
	BOOL eatClear = NO, drinkClear = NO;
	
	// check health
	if ( [playerController health] == [playerController maxHealth] ){
		eatClear = YES;
	}
	else{
		// no buff for eating anyways
		if ( ![auraController unit: player hasBuffNamed: @"Food"] ) {
			eatClear = YES;
		}
	}
	
	// check mana
	if ( [playerController mana] == [playerController maxMana] ){
		drinkClear = YES;
	}
	else{
		// no buff for drinking anyways
		if ( ![auraController unit: player hasBuffNamed: @"Drink"] ) {
			drinkClear = YES;
		}
	}
	
	float timeSinceStart = [[NSDate date] timeIntervalSinceDate: start];
	
	// we're done eating/drinking! continue
	if ( eatClear && drinkClear ){
	
		PGLog(@"[Regen] Finished after %0.2f seconds", timeSinceStart);
		PGLog(@"[Eval] Done drinking");
		[self evaluateSituation];
		return;
	}
	
	// should we be done?
	else if ( timeSinceStart > 30.0f ){
		
		PGLog(@"[Regen] Ran for 30, done!");
		PGLog(@"[Eval] Regen too long");
		[self evaluateSituation];
		return;
	}
	
	[self performSelector: _cmd withObject: start afterDelay: 1.0f];
}


- (Mob*)mobToLoot {
	
    if ( [_mobsToLoot count] ){
    
        Mob *mobToLoot = nil;
        
        // sort the loot list by distance
        [_mobsToLoot sortUsingFunction: DistanceFromPositionCompare context: [playerController position]];
        
        // find a valid mob to loot
        for ( mobToLoot in _mobsToLoot ) {
            if ( mobToLoot && [mobToLoot isValid] && ![blacklistController isBlacklisted:mobToLoot] ) {
                return mobToLoot;
            }
        }
    }
    
    return nil;
}


- (BOOL)evaluateSituation {
    if(![self isBotting])						return NO;
    if(![playerController playerIsValid:self])  return NO;
	
	PGLog(@"[Bot] Evaluate Situation");
    
    [NSObject cancelPreviousPerformRequestsWithTarget: self selector: _cmd object: nil];
	
	// Check for preparation buff
	if ( self.isPvPing && [pvpWaitForPreparationBuff state] && [auraController unit: [playerController player] hasAura: PreparationSpellID] ){
		
		[controller setCurrentStatus: @"PvP: Waiting for preparation buff to fade..."];
		[movementController pauseMovement];
	
		[self performSelector: _cmd withObject: nil afterDelay: 1.0f];
		
		return YES;
	}
	
	// wait for boat to settle!
	if ( self.isPvPing && _strandDelay ){
		[controller setCurrentStatus: @"PvP: Waiting for boat to arrive..."];
		[movementController pauseMovement];
		
		[self performSelector: _cmd withObject: nil afterDelay: 1.0f];
		
		return YES;
	}
	
	// walk off boat
	if ( self.isPvPing && [playerController zone] == 4384 && [playerController isOnBoatInStrand] ){
		[controller setCurrentStatus: @"PvP: Walking off the boat..."];
		
		BOOL onLeftBoat = [playerController isOnLeftBoatInStrand];
		Position *pos = nil;
		
		if ( onLeftBoat ){
			PGLog(@"[PvP] Moving off of left boat!");
			//pos = [Position positionWithX:1609.5f Y:49.6f Z:7.6f];
			pos = [Position positionWithX:6.23f Y:20.94f Z:4.97f];
			
		}
		else{
			PGLog(@"[PvP] Moving off of right boat!");
			//pos = [Position positionWithX:1597.2f Y:-101.4f Z:8.9f];
			pos = [Position positionWithX:5.88f Y:-25.1f Z:5.3f];
		}
		
		// start moving
		[movementController setClickToMove:pos andType:ctmWalkTo andGUID:0x0];

		[self performSelector: _cmd withObject: nil afterDelay: 0.5f];
		
		return YES;
	}
    
    Position *playerPosition = [playerController position];
    //float vertOffset = [[[[NSUserDefaultsController sharedUserDefaultsController] values] valueForKey: @"CombatBlacklistVerticalOffset"] floatValue];
    
    // Order of Operations
    // 1) If we are dead, check to see if we can resurrect.
	// 2) Should we follow a player
    // 3) If we are moving to melee range, return.
    // 4) If we are in combat but not already attacking, scan for mobs to attack.
    // ---- Not in Combat after here ----
    // 5) Check for bodies to loot, loot if necessary.
    // 6) Scan for valid target in range, attack if found.
    // 7) Check for nodes to harvest, harvest if necessary.
    // 8) Resume movement if needed, nothing else to do.
        
    // if the player is a Ghost...
    if( [playerController isGhost]) {
		
        if( [playerController corpsePosition] && [playerPosition distanceToPosition: [playerController corpsePosition]] < 26.0 ) {
            // we found our corpse
            [controller setCurrentStatus: @"Bot: Waiting to Resurrect"];
            [movementController pauseMovement];
            
            // set our next-revive wait timer
            if(!_reviveAttempt) _reviveAttempt = 1;
            else _reviveAttempt = _reviveAttempt*2;
            
            [macroController useMacroOrSendCmd:@"Resurrect"];    // get corpse
			
			if ( _reviveAttempt > 15 ){
				_reviveAttempt = 15;
			}
            
            PGLog(@"Waiting %d seconds to resurrect.", _reviveAttempt);
            [self performSelector: _cmd withObject: nil afterDelay: _reviveAttempt];
            return YES;
        }
        return NO;
    }
	
	// Is the player air mounted, and on the ground?  Me no likely - lets jump!
	UInt32 movementFlags = [playerController movementFlags];
	if ( (movementFlags & 0x1000000) == 0x1000000 && (movementFlags & 0x3000000) != 0x3000000 ){
		if ( _jumpAttempt == 0 && ![controller isWoWChatBoxOpen] ){
			usleep(200000);
			PGLog(@"[Bot] Player on ground, jumping!");
			[chatController jump];
			usleep(10000);
		}
		
		if ( _jumpAttempt++ > 3 )	_jumpAttempt = 0;
	}
	
	// party options
	// auto-queue button name: LFDDungeonReadyDialogueEnterDungeonButton
	if ( theCombatProfile.partyEnabled && theCombatProfile.followUnit && theCombatProfile.followUnitGUID > 0x0 ){
		
		Player *followTarget = [playersController playerWithGUID:theCombatProfile.followUnitGUID];
		
		// follow
		if ( followTarget && [followTarget isValid] ){
			
			// mount?
			if ( theCombatProfile.mountEnabled && [followTarget isMounted] && ![[playerController player] isMounted] && ![playerController isCasting] && ![[playerController player] isSwimming] && ![playerController isInCombat] ){
				
				int theMountType = 1;	// ground
				
				// air
				if ( ![followTarget isOnGround] ){
					theMountType = 2;
				}
				
				// time to mount!
				Spell *mount = [spellController mountSpell:theMountType andFast:YES];
				if ( mount != nil ){
					PGLog(@"[Follow] Mounting...");
					
					[self performAction:[[mount ID] intValue]];
					
					// Check our position again shortly!
					[self performSelector: _cmd withObject: nil afterDelay: 2.0f];
					return YES;
				}
				else{
					// does this player have any mounts?
					if ( [playerController mounts] > 0 && [spellController mountsLoaded] == 0 ){
						PGLog(@"[Bot] Attempting to load mounts...");
						
					}					
				}
			}
			
			// move?
			Position *playerPosition = [[playerController player] position];
			float range = [playerPosition distanceToPosition: [followTarget position]];

			if ( range >= theCombatProfile.followDistanceToMove ) {
				PGLog(@"[Follow] Not within %0.2f yards of target, %0.2f away, moving closer", theCombatProfile.followDistanceToMove, range);
				
				if ( ![playerController isCasting] ){ //&& ![playerController isCTMActive] ){
					[movementController followObject: followTarget];
				}
				
				// Check our position again shortly!
				[self performSelector: _cmd withObject: nil afterDelay: 0.5f];
				
				return YES;
			}
		}
		
		// can't follow
		else{
			PGLog(@"[Follow] No valid target found");
		}
			
	}

    
    // check to see if we are moving to attack a unit and bail if we are
    /*if( combatController.attackUnit && (combatController.attackUnit == [movementController moveToObject])) {
        PGLog(@"attackUnit == moveToObject");
        return NO;
    }*/
	
	// player is in combat already! should we do something?
    if ( [combatController inCombat] ) {
		
		
		// Priorities:
		//	Heal those around us
		//	Kill anything attacking us
		//	Ignore
		

		//validUnitsWithFriendly
		// find a unit to do something with! (could be heal a target or dps)
		Unit *bestUnit = [combatController findUnitWithFriendly:_includeFriendly onlyHostilesInCombat:YES];
		
		// TO DO: we need to do another check here to see if it matches ANY rule in CombatProcedure, otherwise infi loop for a bit :(
		
		// unit found - verify we can actually do something to it
		if ( bestUnit && [self combatProcedureValidForUnit:bestUnit] ){
			
			PGLog(@"[Bot] Found %@ to act on! Doing something ;)", bestUnit);
			
			[self actOnUnit:bestUnit];
			
			[movementController pauseMovement];
			
			return YES;
		}
	}
    
	
    /* *** if we get here, we aren't in combat *** */
    
    // first, check if we are in combat
    // this is to compensate for MovementController calling evaluate while moving to a mob
    //if( [[self procedureInProgress] isEqualToString: CombatProcedure] && [movementController moveToObject] ) {
    //    PGLog(@"CombatProcedure && moveToObject");
    //    return NO;
    //}
	
	// do we need to do regen?  Might have missed it as we were in combat before!
	if ( _doRegenProcedure > 0 ){
		
		_doRegenProcedure++;
		PGLog(@"[Bot] Trying to execute regen procedure %d", _doRegenProcedure);
		
		// only try this a few times
		if ( _doRegenProcedure < 10 ){
			if ( [playerController isInCombat] ){
				PGLog(@"[Bot] Still in combat, waiting to execute regen, trying again in 0.1 seconds");
				[self performSelector:_cmd withObject:nil afterDelay:0.1f];
				return YES;
			}
			
			_doRegenProcedure = 0;
			
			[self executeRegen:NO];
			
			return YES;
		}
		else{
			_doRegenProcedure = 0;
			
			PGLog(@"[Bot] Ignoring regen procedure, evaluating...");
		}
	}
	
    // get potential units and their distances
    Mob *mobToLoot      = [self mobToLoot];
    Unit *unitToActOn  = [combatController findUnitWithFriendly:_includeFriendly onlyHostilesInCombat:NO];
    
    float mobToLootDist     = mobToLoot ? [[mobToLoot position] distanceToPosition: playerPosition] : INFINITY;
    float unitToActOnDist  = unitToActOn ? [[unitToActOn position] distanceToPosition: playerPosition] : INFINITY;
    
    // if the mob to loot is closer to us, loot it first
    if ( mobToLoot && (mobToLootDist < unitToActOnDist ) ) {
		PGLog(@"[Bot] Mob is closer to loot! %0.2f < %0.2f", mobToLootDist, unitToActOnDist);
		
		
		// if the mob is close, just loot it!
		if ( mobToLootDist <= 5.0 ) {
			[self performSelector: @selector(reachedUnit:) withObject: mobToLoot afterDelay: 0.1f];
			
			return YES;
		}
		
		// do we need to start moving to it?
        else if ( mobToLoot != [movementController moveToObject] ) {
			
            if ( [mobToLoot isValid] && (mobToLootDist < INFINITY) ) {
				
				// Looting failed :/ I doubt this will ever actually happen, probably more an issue with nodes, but just in case!
				if ( self.lastAttemptedUnitToLoot == mobToLoot && _lootAttempt >= 3 ){
					PGLog(@"[Loot] Unable to loot %@, removing from loot list", self.lastAttemptedUnitToLoot);
					[_mobsToLoot removeObject: self.unitToLoot];
					
					// potential fix to just stopping?  thanks wowpew
					[movementController resetUnit];
				}
				else{
					PGLog(@"Found mob to loot: %@ at dist %.2f", mobToLoot, mobToLootDist);
					[movementController moveToObject: mobToLoot andNotify: YES];
					return YES;
				}
            }
			else{
				PGLog(@"[Loot] Mob found, but either isn't valid (%d), is too far away (%d)", [mobToLoot isValid], (mobToLootDist < INFINITY) );
			}
        }
		else{
			PGLog(@"[Loot] We're already moving toward %@ (%@)", mobToLoot, [movementController moveToObject]);
			[movementController resumeMovement];
			return YES;
		}
    }
    
    // otherwise, attack the unit
    if ( [unitToActOn isValid] && (unitToActOnDist < INFINITY) && [self combatProcedureValidForUnit:unitToActOn] ) {
		
		PGLog(@"[Bot] Valid unit to act on: %@", unitToActOn);
		
        if ( [combatController combatEnabled] || theCombatProfile.healingEnabled ) {
            

			// hostile only
			if ( [playerController isHostileWithFaction: [unitToActOn factionTemplate]] ) {
				
				// should we do pre-combat?
				if ( ![combatController inCombat] && !_didPreCombatProcedure ) {
					
					_didPreCombatProcedure = YES;
					self.preCombatUnit = unitToActOn;
					
					PGLog(@"[Bot] Starting PreCombat procedure");
					
					[self performProcedureWithState: [NSDictionary dictionaryWithObjectsAndKeys: 
													  PreCombatProcedure,               @"Procedure",
													  [NSNumber numberWithInt: 0],      @"CompletedRules",
													  unitToActOn,                     @"Target",  nil]];
					return YES;
				}
				
				if ( unitToActOn != self.preCombatUnit ) {
					PGLog(@"[Bot] Attacking unit other than pre-combat unit.");
				}
				
				self.preCombatUnit = nil;
				
				// time to attack!
				PGLog(@"[Bot] Found %@ and attacking.", unitToActOn);
				[movementController turnTowardObject: unitToActOn];
			}
			
			[self actOnUnit: unitToActOn];
			
			return YES;
        } else {
            self.preCombatUnit = nil;
        }
    }
	
    // check for mining and herbalism
    if(![movementController moveToObject]) {
        NSMutableArray *nodes = [NSMutableArray array];
        if(_doMining)			[nodes addObjectsFromArray: [nodeController nodesWithinDistance: self.gatherDistance ofType: MiningNode maxLevel: _miningLevel]];
        if(_doHerbalism)		[nodes addObjectsFromArray: [nodeController nodesWithinDistance: self.gatherDistance ofType: HerbalismNode maxLevel: _herbLevel]];
		if(_doNetherwingEgg)	[nodes addObjectsFromArray: [nodeController nodesWithinDistance: self.gatherDistance EntryID: 185915 position:[playerController position]]];
		
        [nodes sortUsingFunction: DistanceFromPositionCompare context: playerPosition];
        
        if([nodes count]) {
            // find a valid node to loot
            Node *nodeToLoot = nil;
            float nodeDist = INFINITY;
            
            for(nodeToLoot in nodes) {

				if ( ![nodeToLoot validToLoot] ){
					PGLog(@"[Bot] Node %@ is not valid to loot, ignoring...", nodeToLoot );
					continue;
				}
				
                if(nodeToLoot && [nodeToLoot isValid] && ![blacklistController isBlacklisted:nodeToLoot]) {
                    nodeDist = [playerPosition distanceToPosition: [nodeToLoot position]];
                    break;
                }
            }
      
			// We have a valid node!
            if([nodeToLoot isValid] && (nodeDist != INFINITY) ) {
				
				BOOL nearbyScaryUnits = [self scaryUnitsNearNode:nodeToLoot doMob:_nodeIgnoreMob doFriendy:_nodeIgnoreFriendly doHostile:_nodeIgnoreHostile];
				
				if ( !nearbyScaryUnits ){
					[controller setCurrentStatus: @"Bot: Moving to node"];
					
					[movementController pauseMovement];
					PGLog(@"[Loot] Found closest node to loot: %@ at dist %.2f", nodeToLoot, nodeDist);
					if(nodeDist <= NODE_DISTANCE_UNTIL_DISMOUNT){
						if ( self.lastAttemptedUnitToLoot == nodeToLoot && _lootAttempt >= 3 ){
							
							PGLog(@"[Loot] Unable to loot %@, should we add this to a blacklist?", self.lastAttemptedUnitToLoot);
						}
						else{
							[self reachedUnit: nodeToLoot];
							return YES;
						}
					}
					// Should we be mounted before we move to the node?
					else if ( [self mountNow] ){
						PGLog(@"mounting...");
						[self performSelector: _cmd withObject: nil afterDelay: 2.0f];	
						return YES;
					}
					// Safe to move to the node!
					else{
						[movementController moveToObject: nodeToLoot andNotify: YES];
					}
					return YES;
				}
            }
        }
    }
	
	// check for fishing
	if ( ![movementController moveToObject] ){
		if ( _doFishing ){
			
			PGLog(@"[Bot] Fishing scan!");
			
			// fishing only in schools! (probably have a route we're following)
			if ( _fishingOnlySchools ){
				NSMutableArray *nodes = [NSMutableArray array];
				[nodes addObjectsFromArray:[nodeController nodesWithinDistance:_fishingGatherDistance ofType: FishingSchool maxLevel: 1]];
				[nodes sortUsingFunction: DistanceFromPositionCompare context: playerPosition];
				
				// are we close enough to start fishing?
				if ( [nodes count] ){
					
					// lets find a node
					Node *nodeToFish = nil;
					float nodeDist = INFINITY;
					for(nodeToFish in nodes) {
						
						if ( [blacklistController isBlacklisted:nodeToFish] ){
							PGLog(@"[Bot] Node %@ blacklisted, ignoring", nodeToFish);
							continue;
						}
						
						if ( nodeToFish && [nodeToFish isValid] ) {
							nodeDist = [playerPosition distanceToPosition: [nodeToFish position]];
							break;
						}
					}
					
					BOOL nearbyScaryUnits = [self scaryUnitsNearNode:nodeToFish doMob:_nodeIgnoreMob doFriendy:_nodeIgnoreFriendly doHostile:_nodeIgnoreHostile];
					
					// we have a valid node!
					if ( [nodeToFish isValid] && (nodeDist != INFINITY) && !nearbyScaryUnits ) {
						[movementController pauseMovement];
						
						PGLog(@"[Bot] Found closest school %@ at dist %.2f", nodeToFish, nodeDist);
						if(nodeDist <= NODE_DISTANCE_UNTIL_FISH){
							
							// turn toward
							[movementController turnTowardObject:nodeToFish];
							[movementController backEstablishPosition];
							
							// add some blacklisting logic here...
							
							// now we fish!
							
							PGLog(@"[Bot] We are near %@, time to fish!", nodeToFish);
							
							if ( [[playerController player] isMounted] ){
								PGLog(@"[Bot] Dismounting...");
								[movementController dismount]; 
							}
							
							if ( ![fishController isFishing] ){
								[fishController fish: _fishingApplyLure
										  withRecast:_fishingRecast
											 withUse:_fishingUseContainers
											withLure:_fishingLureSpellID
										  withSchool:nodeToFish];
							}
							
							return YES;
						}
						/*
						// Should we be mounted before we move to the node?
						else if ( [self mountNow] ){
							[self performSelector: _cmd withObject: nil afterDelay: 2.2f];	
							return YES;
						}
						// Safe to move to the node!
						else{
							[controller setCurrentStatus: @"Bot: Moving to fishing pool"];
							[movementController moveToObject: nodeToFish andNotify: YES];
						}
						return YES;*/
					}
				}
				
				PGLog(@"[Fishing] Didn't find a node, so we're doing nothing...");
			}
			
			// fish where we are
			else{
				PGLog(@"[Fishing] Just fishing from wherever we are!");
				
				[fishController fish: _fishingApplyLure
						  withRecast:NO
							 withUse:_fishingUseContainers
							withLure:_fishingLureSpellID
						  withSchool:nil];		
				
				return YES;
			}
			
			// if we get here, we shouldn't be fishing, stop if we are
			if ( [fishController isFishing] ){
				[fishController stopFishing];
			}
		}
	}
	
	// Should we be mounted?
	if ( ![movementController moveToObject] && [self mountNow] ){
		PGLog(@"mounting.....");
		[self performSelector: _cmd withObject: nil afterDelay: 2.0f];	
		return YES;
	}
    
    // if there's nothing to do, make sure we keep moving if we aren't
    if(self.theRoute) {
        if([movementController isPatrolling] && ([movementController patrolRoute] == [self.theRoute routeForKey: PrimaryRoute])) {
			PGLog(@"[Bot] Eval: resuming movement");
            [movementController resumeMovementToNearestWaypoint];
        } else {
            [movementController setPatrolRoute: [self.theRoute routeForKey: PrimaryRoute]];
            [movementController beginPatrol: 0 andAttack: self.theCombatProfile.combatEnabled];
        }
        [controller setCurrentStatus: @"Bot: Patrolling"];
    } else {
        [controller setCurrentStatus: @"Bot: Enabled"];
        [self performSelector: _cmd withObject: nil afterDelay: 0.1];
    }
    return NO;
}

-(BOOL)mountNow{
	
	// some error checking
	if ( _mountAttempt > 8 ){
		float timeUntilRetry = 15.0f - (-1.0f * [_mountLastAttempt timeIntervalSinceNow]);
		
		if ( timeUntilRetry > 0.0f ){
			PGLog(@"[Bot] Will not mount for another %0.2f seconds", timeUntilRetry );
			return NO;
		}
		else{
			_mountAttempt = 0;
		}
	}
	
	if ( [mountCheckbox state] && ([miningCheckbox state] || [herbalismCheckbox state] || [fishingCheckbox state]) && ![[playerController player] isSwimming] && ![[playerController player] isMounted] && ![playerController isInCombat] && ![playerController isIndoors] ){
		
		_mountAttempt++;
		
		PGLog(@"[Bot] Mounting attempt %d! Movement flags: 0x%X", _mountAttempt, [playerController movementFlags]);

		// record our last attempt
		[_mountLastAttempt release]; _mountLastAttempt = nil;
		_mountLastAttempt = [[NSDate date] retain];
		
		// actually mount
		Spell *mount = [spellController mountSpell:[mountType selectedTag] andFast:YES];
		if ( mount ){
			
			// stop moving if we need to!
			[movementController pauseMovement];
			usleep(100000);
			
			// Time to cast!
			int errID = [self performAction:[[mount ID] intValue]];
			if ( errID == ErrNone ){
				
				PGLog(@"[Bot] Mounting started! No errors!");
				
				_mountAttempt = 0;
				
				return YES;
			}
			PGLog(@"[Bot] Mounting failed! Error: %d", errID);
		}
		else{
			PGLog(@"[Bot] No mounts found! PG will try to load them, you can do it manually on your spells tab 'Load All'");
			
			// should we load any mounts
			if ( [playerController mounts] > 0 && [spellController mountsLoaded] == 0 ){
				PGLog(@"[Bot] Attempting to load mounts...");
				[spellController reloadPlayerSpells];				
			}	
		}
	}
	
	return NO;
}

#pragma mark IBActions


- (IBAction)editCombatProfiles: (id)sender {
    [[CombatProfileEditor sharedEditor] showEditorOnWindow: [self.view window] 
                                           forProfileNamed: [[NSUserDefaults standardUserDefaults] objectForKey: @"CombatProfile"]];
}

- (IBAction)updateStatus: (id)sender {
    CombatProfile *profile = [[combatProfilePopup selectedItem] representedObject];
	
    NSString *status = [NSString stringWithFormat: @"%@ (%@). ", 
                        [[[behaviorPopup selectedItem] representedObject] name],    // behavior
                        [[[routePopup selectedItem] representedObject] name]];       // route
    
    NSString *bleh = nil;
    if(!profile || !profile.combatEnabled) {
        bleh = @"Combat disabled.";
    } else {
        if(profile.onlyRespond) {
            bleh = @"Only attacking back.";
        }
		else if ( profile.assistUnit ){
				
			bleh = [NSString stringWithFormat:@"Only assisting %@", @""];
		}
		else{
            NSString *levels = profile.attackAnyLevel ? @"any levels" : [NSString stringWithFormat: @"levels %d-%d", 
                                                                         profile.attackLevelMin,
                                                                         profile.attackLevelMax];
            bleh = [NSString stringWithFormat: @"Attacking %@ within %.1fy.", 
                    levels,
                    profile.engageRange];
        }
    }
    
    status = [status stringByAppendingString: bleh];
    
    
    if([miningCheckbox state])
        status = [status stringByAppendingFormat: @" Mining (%d).", [miningSkillText intValue]];
    if([herbalismCheckbox state])
        status = [status stringByAppendingFormat: @" Herbalism (%d).", [herbalismSkillText intValue]];
    if([skinningCheckbox state])
        status = [status stringByAppendingFormat: @" Skinning (%d).", [skinningSkillText intValue]];
	
	BOOL enableMount = NO;
	
	// enable our any mount
	if ( [miningCheckbox state] || [herbalismCheckbox state] || [netherwingEggCheckbox state] || [fishingCheckbox state] ){
		enableMount = YES;
	}
	
	// don't enable if looting! Sorry it doesn't work correctly yet!
	if ( [lootCheckbox state] || [skinningCheckbox state] ){
		enableMount = NO;
	}
	
	
	if ( enableMount ){
		[mountCheckbox setEnabled:YES];
		[mountType setEnabled:YES];
	}
	else{
		[mountCheckbox setEnabled:NO];
		[mountType setEnabled:NO];
		[mountCheckbox setState:0];
	}
    
    [statusText setStringValue: status];
}


- (IBAction)startBot: (id)sender {
     BOOL ignoreRoute = [[[[NSUserDefaultsController sharedUserDefaultsController] values] valueForKey: @"IgnoreRoute"] boolValue];
    
    // gather appropriate information to start the bot
    if(ignoreRoute) {
        self.theRoute = nil;
    } else {
        self.theRoute = [[routePopup selectedItem] representedObject];
    }
    self.theBehavior = [[behaviorPopup selectedItem] representedObject];
    self.theCombatProfile = [[combatProfilePopup selectedItem] representedObject];
	PGLog(@"[Bot] Starting with attack range of %0.2f to %0.2f", [self.theCombatProfile engageRange], [self.theCombatProfile attackRange]);
    
    // get hotkey settings
    KeyCombo hotkey = [shortcutRecorder keyCombo];
    _currentHotkeyModifier = hotkey.flags;
    _currentHotkey = hotkey.code;
    hotkey = [petAttackRecorder keyCombo];
    _currentPetAttackHotkeyModifier = hotkey.flags;
    _currentPetAttackHotkey = hotkey.code;
    
    self.doLooting = [lootCheckbox state];
    self.gatherDistance = [gatherDistText floatValue];
	
	// We only really need this if we are PvPing, but we want to store it in case they click "start bot" while in a BG, vs. doing the PvP route
	_pvpMarks = [itemController pvpMarks];
    
	if ( ([self isHotKeyInvalid] & HotKeyPrimary) == HotKeyPrimary ){
        PGLog(@"Primary hotkey is not valid.");
        NSBeep();
        NSRunAlertPanel(@"Invalid Hotkey", @"You must choose a valid primary hotkey, or the bot will be unable to use any spells or abilities.", @"Okay", NULL, NULL);
        return;
    }
	
	if ( self.doLooting && ([self isHotKeyInvalid] & HotKeyInteractMouseover) == HotKeyInteractMouseover ){
        PGLog(@"Interact with MouseOver hotkey is not valid.");
        NSBeep();
        NSRunAlertPanel(@"Invalid Looting Hotkey", @"You must choose a valid Interact with MouseOver hotkey, or the bot will be unable to loot bodies.", @"Okay", NULL, NULL);
        return;
	}
    
    // check that we have valid conditions
    if( ![controller isWoWOpen]) {
        PGLog(@"WoW is not open. Bailing.");
        NSBeep();
        NSRunAlertPanel(@"WoW is not open", @"WoW is not open...", @"Okay", NULL, NULL);
        return;
    }
    
    if( ![playerController playerIsValid:self]) {
        PGLog(@"[Bot] The player is not valid. Bailing.");
        NSBeep();
        NSRunAlertPanel(@"Player not valid or cannot be detected", @"You must be logged into the game before you can start the bot.", @"Okay", NULL, NULL);
        return;
    }
    
    if( !self.theRoute && !ignoreRoute ) {
        NSBeep();
        PGLog(@"[Bot] The current route is not valid.");
        NSRunAlertPanel(@"Route is not valid", @"You must select a valid route before starting the bot.  If you removed or renamed a route, please select an alternative.", @"Okay", NULL, NULL);
        
        return;
    }
    
    if( !self.theBehavior ) {
        PGLog(@"[Bot] The current behavior is not valid.");
        NSBeep();
        NSRunAlertPanel(@"Behavior is not valid", @"You must select a valid behavior before starting the bot.  If you removed or renamed a behavior, please select an alternative.", @"Okay", NULL, NULL);
        return;
    }

    if( !self.theCombatProfile ) {
        PGLog(@"[Bot] The current combat profile is not valid.");
        NSBeep();
        NSRunAlertPanel(@"Combat Profile is not valid", @"You must select a valid combat profile before starting the bot.  If you removed or renamed a profile, please select an alternative.", @"Okay", NULL, NULL);
        return;
    }

    
    if( [self isBotting])
        [self stopBot: nil];
    
    if(self.theCombatProfile && self.theBehavior && (_currentHotkey >= 0)) {
        PGLog(@"[Bot] Starting.");
        [spellController reloadPlayerSpells];
        
        // also check that the route has any waypoints
        // and that the behavior has any procedures
        _doMining			= [miningCheckbox state];
		_doNetherwingEgg	= [netherwingEggCheckbox state];
        _miningLevel		= [miningSkillText intValue];
        _doHerbalism		= [herbalismCheckbox state];
        _herbLevel			= [herbalismSkillText intValue];
        _doSkinning			= [skinningCheckbox state];
        _skinLevel			= [skinningSkillText intValue];
        
		// fishing
		_doFishing				= [fishingCheckbox state];
		_fishingGatherDistance	= [fishingGatherDistanceText floatValue];
		_fishingApplyLure		= [fishingApplyLureCheckbox state];
		_fishingOnlySchools		= [fishingOnlySchoolsCheckbox state];
		_fishingRecast			= [fishingRecastCheckbox state];
		_fishingUseContainers	= [fishingUseContainersCheckbox state];
		_fishingLureSpellID		= [fishingLurePopUpButton selectedTag];
		
		// node checking
		_nodeIgnoreFriendly				= [nodeIgnoreFriendlyCheckbox state];
		_nodeIgnoreHostile				= [nodeIgnoreHostileCheckbox state];
		_nodeIgnoreMob					= [nodeIgnoreMobCheckbox state];
		_nodeIgnoreFriendlyDistance		= [nodeIgnoreFriendlyDistanceText floatValue];
		_nodeIgnoreHostileDistance		= [nodeIgnoreHostileDistanceText floatValue];
		_nodeIgnoreMobDistance			= [nodeIgnoreMobDistanceText floatValue];
		
		_lootUseItems					= [lootUseItemsCheckbox state];
		
		// friendly shit
		
		_includeFriendly = [self includeFriendlyInCombat];
		
		// start our log out timer - only check every 5 seconds!
		_logOutTimer = [NSTimer scheduledTimerWithTimeInterval: 5.0f target: self selector: @selector(logOutTimer:) userInfo: nil repeats: YES];
		
        int canSkinUpToLevel = 0;
        if(_skinLevel <= 100) {
            canSkinUpToLevel = (_skinLevel/10)+10;
        } else {
            canSkinUpToLevel = (_skinLevel/5);
        }
        // PGLog(@"Starting bot with Sknning skill %d, allowing mobs up to level %d", _skinLevel, canSkinUpToLevel);
        
        self.isBotting = YES;
        [startStopButton setTitle: @"Stop Bot"];
        _didPreCombatProcedure = NO;
        _reviveAttempt = 0;
		
		// Bot started, lets reset our whisper history!
		[chatLogController clearWhisperHistory];
        
		if ( !self.isPvPing || self.startDate == nil ){
			self.startDate = [[NSDate date] retain];
		}
        
        if( [playerController isGhost] && self.theRoute) {
            Position *playerPosition = [playerController position];
            Route *primaryRoute  = [self.theRoute routeForKey: PrimaryRoute];
            Route *corpseRunRoute = [self.theRoute routeForKey: CorpseRunRoute];
            
            PGLog(@"[Bot] Started the bot, but we're a ghost!");
            
            float primaryDist = primaryRoute ? [[[primaryRoute waypointClosestToPosition: playerPosition] position] distanceToPosition: playerPosition] : INFINITY;
            float corpseDist = corpseRunRoute ? [[[corpseRunRoute waypointClosestToPosition: playerPosition] position] distanceToPosition: playerPosition] : INFINITY;
            
            if(primaryDist < corpseDist)
                [movementController setPatrolRoute: primaryRoute];
            else
                [movementController setPatrolRoute: corpseRunRoute];
            
            [movementController beginPatrol: 1 andAttack: NO];
            return;
        }
        
        if( [playerController isDead]) {
            PGLog(@"[Bot] Started the bot, but we're dead! Will try to release. (%d:%d:%d:%d)", [playerController health], [playerController isGhost], [playerController maxHealth], [[playerController player] maxHealth] );
            [self playerHasDied: nil];
            return;
        }
        
        [controller setCurrentStatus: @"Bot: Enabled"];
        //[combatController setCombatEnabled: self.theCombatProfile.combatEnabled];
        // [movementController setPatrolRoute: [self.theRoute routeForKey: PrimaryRoute]];
        
		/*
        // if we're in combat when we start, have the mobController update
        if([combatController inCombat] && [[playerController player] isOnGround] ) {
			
			PGLog(@"[Bot] In combat! Finding someone to attack!");

			// these are weighted!
            for ( Unit *unit in [combatController combatList] ) {
				
				// by calling attackUnit, we're basically just starting a CombatProcedure (which could switch the target!)
				[self actOnUnit:unit];
            }
        }*/

		PGLog(@"[Eval] StartBot");
        [self evaluateSituation];
    }
}

- (void)updateRunningTimer{
	int duration = (int) [[NSDate date] timeIntervalSinceDate: self.startDate];
	
	NSMutableString *runningFor = [NSMutableString stringWithFormat:@"Running for: "];
	
	if ( duration > 0 ){
		// Prob a better way for this heh
		int seconds = duration % 60;
		duration /= 60;
		int minutes = duration % 60;
		duration /= 60;
		int hours = duration % 24;
		duration /= 24;
		int days = duration;
		
		if (days > 0) [runningFor appendString:[NSString stringWithFormat:@"%d day%@", days, (days > 1) ? @"s " : @" "]];
		if (hours > 0) [runningFor appendString:[NSString stringWithFormat:@"%d hour%@", hours, (hours > 1) ? @"s " : @" "]];
		if (minutes > 0) [runningFor appendString:[NSString stringWithFormat:@"%d minute%@", minutes, (minutes > 1) ? @"s " : @" "]];
		if (seconds > 0) [runningFor appendString:[NSString stringWithFormat:@"%d second%@", seconds, (seconds > 1) ? @"s " : @""]];
		
		[runningTimer setStringValue: runningFor];
	}
}

- (IBAction)stopBot: (id)sender {
	
	// Then a user clicked!
	if ( sender != nil ){
		self.startDate = nil;
	}
	PGLog(@"Bot Stopped: %@", sender);
    [self cancelCurrentProcedure];
    [movementController setPatrolRoute: nil];
    [combatController resetAllCombat];

    [_mobsToLoot removeAllObjects];
    self.isBotting = NO;
    self.preCombatUnit = nil;
    [controller setCurrentStatus: @"Bot: Stopped"];
    
    PGLog(@"[Bot] Stopped.");
	
	// stop our log out timer
	[_logOutTimer invalidate];_logOutTimer=nil;
    
    if(self.isPvPing) {
        PGLog(@"[Bot] Bot stopped but PvP is ongoing...");
    }
    
    [startStopButton setTitle: @"Start Bot"];
}

- (void)reEnableStart {
    [startStopButton setEnabled: YES];
    [pvpStartStopButton setEnabled: YES];
}

- (IBAction)startStopBot: (id)sender {
    if(self.isBotting) {
        [self stopBot: sender];
    } else {
        [self startBot: sender];
    }
}

NSMutableDictionary *_diffDict = nil;
- (IBAction)testHotkey: (id)sender {
    //int value = 28734;
    //[[controller wowMemoryAccess] saveDataForAddress: ([offsetController offset:@"HOTBAR_BASE_STATIC"] + BAR6_OFFSET) Buffer: (Byte *)&value BufLength: sizeof(value)];
    //PGLog(@"Set Mana Tap.");
    
    KeyCombo hotkey = [shortcutRecorder keyCombo];
    [chatController pressHotkey: hotkey.code withModifier: hotkey.flags];
    
    
    if(!_diffDict) _diffDict = [[NSMutableDictionary dictionary] retain];
    
    BOOL firstRun = ([_diffDict count] == 0);
    UInt32 i, value;
    
    if(firstRun) {
        PGLog(@"First run.");
        for(i=0x900000; i< 0xFFFFFF; i+=4) {
            if([[controller wowMemoryAccess] loadDataForObject: self atAddress: i Buffer: (Byte *)&value BufLength: sizeof(value)]) {
                if(value < 2)
                    [_diffDict setObject: [NSNumber numberWithUnsignedInt: value] forKey: [NSNumber numberWithUnsignedInt: i]];
            }
        }
    } else {
        NSMutableArray *removeKeys = [NSMutableArray array];
        for(NSNumber *key in [_diffDict allKeys]) {
            if([[controller wowMemoryAccess] loadDataForObject: self atAddress: [key unsignedIntValue] Buffer: (Byte *)&value BufLength: sizeof(value)]) {
                if( value == [[_diffDict objectForKey: key] unsignedIntValue]) {
                    [removeKeys addObject: key];
                } else {
                    [_diffDict setObject: [NSNumber numberWithUnsignedInt: value] forKey: key];
                }
            }
        }
        [_diffDict removeObjectsForKeys: removeKeys];
    }
    
    PGLog(@"%d values.", [_diffDict count]);
    if([_diffDict count] < 20) {
        PGLog(@"%@", _diffDict);
    }
    
    return;
}


- (IBAction)hotkeyHelp: (id)sender {
	[NSApp beginSheet: hotkeyHelpPanel
	   modalForWindow: [self.view window]
		modalDelegate: nil
	   didEndSelector: nil
		  contextInfo: nil];
}

- (IBAction)closeHotkeyHelp: (id)sender {
    [NSApp endSheet: hotkeyHelpPanel returnCode: 1];
    [hotkeyHelpPanel orderOut: nil];
}

- (IBAction)lootHotkeyHelp: (id)sender {
	[NSApp beginSheet: lootHotkeyHelpPanel
	   modalForWindow: [self.view window]
		modalDelegate: nil
	   didEndSelector: nil
		  contextInfo: nil];
}

- (IBAction)closeLootHotkeyHelp: (id)sender {
    [NSApp endSheet: lootHotkeyHelpPanel returnCode: 1];
    [lootHotkeyHelpPanel orderOut: nil];
}

- (IBAction)gatheringLootingOptions: (id)sender{
	[NSApp beginSheet: gatheringLootingPanel
	   modalForWindow: [self.view window]
		modalDelegate: self
	   didEndSelector: @selector(gatheringLootingDidEnd: returnCode: contextInfo:)
		  contextInfo: nil];
}

- (IBAction)gatheringLootingSelectAction: (id)sender {
    [NSApp endSheet: gatheringLootingPanel returnCode: [sender tag]];
}

- (void)gatheringLootingDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo {
    [gatheringLootingPanel orderOut: nil];
}

// sometimes queueing for the BG fails, so lets just check every second to make sure we queued
- (void)queueForBGCheck{
	int status = [playerController battlegroundStatus];
	if ( status == BGWaiting ){
		// queue then check again!
		[macroController useMacroOrSendCmd:@"AcceptBattlefield"];
		[self performSelector:@selector(queueForBGCheck) withObject: nil afterDelay:1.0f];
		PGLog(@"[PvP] Additional join BG check executed!");
	}
}


#pragma mark Notifications

- (void)eventBattlegroundStatusChange: (NSNotification*)notification{
	if ( ![self isPvPing] ) return;
	
	int status = [[notification object] intValue];
	
	// Lets join the BG!
	if ( status == BGWaiting ){
		//[macroController useMacroOrSendCmd:@"AcceptBattlefield"];
		float queueAfter = SSRandomFloatBetween(3.0f, 20.0f);
		[self performSelector:@selector(queueForBGCheck) withObject: nil afterDelay:queueAfter];
		PGLog(@"[PvP] Joining the BG after %0.2f seconds", queueAfter);
	}
	else if ( status == BGNone ){
		// just stop movement
		[movementController resetMovementState];
		PGLog(@"[PvP] Battleground is over?? Resetting movement state");
	}
}

- (void)eventZoneChanged: (NSNotification*)notification{
	if ( ![self isBotting] ) return;
	
	NSNumber *lastZone = [notification object];
	
	if ( [playerController isInBG:[lastZone intValue]] ){
		[self stopBot:nil];
		PGLog(@"[PvP] Left BG, stopping bot!");
		//asdfasfsafd TO FIX
	}
	
	PGLog(@"[Bot] Zone change fired... to %@", lastZone);
}

// Want to respond to some commands? o.O
- (void)whisperReceived: (NSNotification*)notification{
	ChatLogEntry *entry = [notification object];
	
	//TO DO: Check to make sure you only respond to people around you that you are healing!
	
	if ( [[entry text] isEqualToString: @"stay"] ){
		PGLog(@"[Heal] Stop following");
		_shouldFollow = NO;
	}
	else if ( [[entry text] isEqualToString: @"heel"] ){
		PGLog(@"[Heal] Start following again!");
		_shouldFollow = YES;
	}
}

#pragma mark AKA [Input] PlayerData

- (void)playerHasRevived: (NSNotification*)notification {
    if( ![self isBotting]) return;
    PGLog(@"---- Player has revived!");
    [controller setCurrentStatus: @"Bot: Player has Revived"];
    [NSObject cancelPreviousPerformRequestsWithTarget: self];
    _reviveAttempt = 0;
    
    // rescan for mobs
    // [mobController enumerateAllMobs];
    
    // reset our route and then pause again
    if(self.theRoute) {
        [movementController setPatrolRoute: [self.theRoute routeForKey: PrimaryRoute]];
        [movementController beginPatrol: 0 andAttack: self.theCombatProfile.combatEnabled];
        [movementController pauseMovement];
    }
    
    // perform post combat
    [self performSelector: @selector(performProcedureWithState:) 
               withObject: [NSDictionary dictionaryWithObjectsAndKeys: 
                            PostCombatProcedure,              @"Procedure",
                            [NSNumber numberWithInt: 0],      @"CompletedRules", nil] 
               afterDelay: 1.0];
}

- (void)playerHasDied: (NSNotification*)notification {
    
    if( ![self isBotting]) return;
	if ( ![playerController playerIsValid:self] ) return;
	
    PGLog(@"---- Player has died.");
    [controller setCurrentStatus: @"Bot: Player has Died"];
    
    [self cancelCurrentProcedure];              // this wipes all bot state (except pvp)
    [movementController setPatrolRoute: nil];   // this wipes all movement state
    [combatController resetAllCombat];         // this wipes all combat state
	
	_shouldFollow = YES;
    
    // send notification to Growl
    if( [controller sendGrowlNotifications] && [GrowlApplicationBridge isGrowlInstalled] && [GrowlApplicationBridge isGrowlRunning]) {
        // [GrowlApplicationBridge setGrowlDelegate: @""];
        [GrowlApplicationBridge notifyWithTitle: @"Player Has Died!"
                                    description: @"Sorry :("
                               notificationName: @"PlayerDied"
                                       iconData: [[NSImage imageNamed: @"Ability_Warrior_Revenge"] TIFFRepresentation]
                                       priority: 0
                                       isSticky: NO
                                   clickContext: nil];
    }
	
	// Try to res in a second! (give the addon time to release if they're using one!)
    [self performSelector: @selector(rePop:) withObject: [NSNumber numberWithInt:0] afterDelay: 3.0f];
	
	
	// Play an alarm after we die?
	if ( [[[[NSUserDefaultsController sharedUserDefaultsController] values] valueForKey: @"AlarmOnDeath"] boolValue] ){
		[[NSSound soundNamed: @"alarm"] play];
		PGLog(@"Playing alarm, you have died!");
	}
}

- (void)rePop: (NSNumber *)count{
	if( ![self isBotting]) return;
	if ( ![playerController playerIsValid:self] ) return;
	
	if ( theCombatProfile.disableRelease ){
		PGLog(@"[Bot] Ignoring release due to a combat setting");
		return;
	}

	PGLog(@"[Bot] Trying to repop (%d:%d)", [playerController isGhost], [playerController isDead] );
	
	// We need to repop!
	if ( ![playerController isGhost] && [playerController isDead] ) {
		int try = [count intValue];
		// ONLY stop bot if we're not in PvP (we'll auto res in PvP!)
		if(++try > 10 && !self.isPvPing) {
			PGLog(@"[Bot] Repop failed after 10 tries.  Stopping bot.");
			[self stopBot: nil];
			[controller setCurrentStatus: @"Bot: Failed to Release. Stopped."];
			return;
		}
		PGLog(@"[Bot] Attempting to repop %d.", try);
		
		[macroController useMacroOrSendCmd:@"ReleaseCorpse"];
		
		// Try again every 5 seconds pls
		[self performSelector: @selector(rePop:) withObject: [NSNumber numberWithInt:try] afterDelay: 5.0];
	}
	
	// We're a ghost w00t! Lets start the route!
	else{
		// run back if we have a route
		if(!self.isPvPing) {
			if([self.theRoute routeForKey: CorpseRunRoute] && ![playerController isInBG:[playerController zone]]) {
				PGLog(@"[Bot] Starting Corpse Run...");
				[controller setCurrentStatus: @"Bot: Running back from graveyard..."];
				[movementController setPatrolRoute: [self.theRoute routeForKey: CorpseRunRoute]];
				[movementController beginPatrolAndStopAtLastPoint];
			}
		} else {
			PGLog(@"[PvP] Ignoring Corpse Run route because we are PvPing.");
		}
	}
}

- (void)playerIsInvalid: (NSNotification*)not {
    if( [self isBotting]) {
        PGLog(@"[Bot] Player is no longer valid, stopping bot.");
        [self stopBot: nil];
    }
}

#pragma mark ShortcutRecorder Delegate

- (void)toggleGlobalHotKey:(SRRecorderControl*)sender
{
	if (StartStopBotGlobalHotkey != nil) {
		[[PTHotKeyCenter sharedCenter] unregisterHotKey: StartStopBotGlobalHotkey];
		[StartStopBotGlobalHotkey release];
		StartStopBotGlobalHotkey = nil;
	}
    
    KeyCombo keyCombo = [sender keyCombo];
    
    if((keyCombo.code >= 0) && (keyCombo.flags >= 0)) {
        StartStopBotGlobalHotkey = [[PTHotKey alloc] initWithIdentifier: @"StartStopBot"
                                                               keyCombo: [PTKeyCombo keyComboWithKeyCode: keyCombo.code
                                                                                               modifiers: [sender cocoaToCarbonFlags: keyCombo.flags]]];
        
        [StartStopBotGlobalHotkey setTarget: startStopButton];
        [StartStopBotGlobalHotkey setAction: @selector(performClick:)];
        
        [[PTHotKeyCenter sharedCenter] registerHotKey: StartStopBotGlobalHotkey];
    }
}

- (void)shortcutRecorder:(SRRecorderControl *)recorder keyComboDidChange:(KeyCombo)newKeyCombo {
    if(recorder == shortcutRecorder) {
        [[NSUserDefaults standardUserDefaults] setObject: [NSNumber numberWithInt: newKeyCombo.code] forKey: @"HotkeyCode"];
        [[NSUserDefaults standardUserDefaults] setObject: [NSNumber numberWithInt: newKeyCombo.flags] forKey: @"HotkeyFlags"];
    }
    
    if(recorder == startstopRecorder) {
       [[NSUserDefaults standardUserDefaults] setObject: [NSNumber numberWithInt: newKeyCombo.code] forKey: @"StartstopCode"];
       [[NSUserDefaults standardUserDefaults] setObject: [NSNumber numberWithInt: newKeyCombo.flags] forKey: @"StartstopFlags"];
       [self toggleGlobalHotKey: startstopRecorder];
    }
    
    if(recorder == petAttackRecorder) {
        [[NSUserDefaults standardUserDefaults] setObject: [NSNumber numberWithInt: newKeyCombo.code] forKey: @"PetAttackCode"];
        [[NSUserDefaults standardUserDefaults] setObject: [NSNumber numberWithInt: newKeyCombo.flags] forKey: @"PetAttackFlags"];
    }
    
    if(recorder == mouseOverRecorder) {
        [[NSUserDefaults standardUserDefaults] setObject: [NSNumber numberWithInt: newKeyCombo.code] forKey: @"MouseOverTargetCode"];
        [[NSUserDefaults standardUserDefaults] setObject: [NSNumber numberWithInt: newKeyCombo.flags] forKey: @"MouseOverTargetFlags"];
    }
	
    [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark -
#pragma mark PvP!

- (void)auraGain: (NSNotification*)notification {

	// Player is PvPing!
    if(self.isPvPing) {
        UInt32 spellID = [[(Spell*)[[notification userInfo] objectForKey: @"Spell"] ID] unsignedIntValue];
		
		// if we are waiting to rez, pause the bot (incase it is not)
        if( spellID == WaitingToRezSpellID ) {
            [movementController pauseMovement];
			
        }
		
		// Just got preparation?  Lets check to see if we're in strand + should be attacking/defending
        if( spellID == PreparationSpellID ) {
			PGLog(@"We have preparation, checking BG info!");
			
			// Do it in a bit, as we need to wait for our controller to update the object list!
			[self performSelector:@selector(pvpGetBGInfo) withObject:nil afterDelay:3.1f];
        }
    }
}

- (void)auraFade: (NSNotification*)notification {
	
	// Player is PvPing!
    if(self.isPvPing) {
        UInt32 spellID = [[(Spell*)[[notification userInfo] objectForKey: @"Spell"] ID] unsignedIntValue];
		
        if( spellID == PreparationSpellID ) {

			// Only checking for the delay!
			if ( [playerController isOnBoatInStrand] && [playerController zone] == ZoneStrandOfTheAncients ){
				// We want to pause, and not move until the boat stops!  Delay 10 seconds?
				[movementController pauseMovement];
				
				_strandDelay = YES;
				
				// reset the delay in 10 seconds?
				[self performSelector:@selector(pvpResetStrandDelay) withObject:nil afterDelay:10.0f];
				
				PGLog(@"[PvP] We are on a boat in Strand! Starting a delay until the boat stops!");
			}
        }
    }
}

- (void)pvpResetStrandDelay{
	_strandDelay = NO;
	
	PGLog(@"[PvP] Delay reset!");
	
	[controller setCurrentStatus: @"PvP: Delay reset, am I really waiting for eval?..."];
	
	PGLog(@"[Eval] Reset strand");
	[self performSelector:@selector(evaluateSituation) withObject:nil afterDelay:10.0f];
}

- (void)pvpGetBGInfo{
	
	// Lets gets some info?
	if ( [playerController zone] == ZoneStrandOfTheAncients ){
		// Determine what the player is!
		//int faction = [playerController factionTemplate];
		
		/*BOOL isAlliance = ([controller reactMaskForFaction: faction] & 0x2);
		BOOL isHorde = ([controller reactMaskForFaction: faction] & 0x4);
					   
		PGLog(@"Alliance: %d, Horde: %d", isAlliance, isHorde);*/
		
		/*
		Position *playerPosition = [playerController position];
		NSArray *allianceNodes = [NSArray arrayWithObjects:
								   [NSNumber numberWithInt:StrandAllianceBanner],
								   [NSNumber numberWithInt:StrandAllianceBannerAura],
								   nil];
		NSArray *hordeNodes = [NSArray arrayWithObjects:
								  [NSNumber numberWithInt:StrandHordeBanner],
								  [NSNumber numberWithInt:StrandeHordeBannerAura],
								  nil];
		
		// Since we're only check @ the start, we just have to check to see which exist @ the beginning!
		if ( [[nodeController nodesWithinDistance: 5000.0f NodeIDs:allianceNodes position:playerPosition] count] > 0 ){
			PGLog(@"[PvP] Alliance is defending in strand!");
			if ( isHorde ){
				_attackingInStrand = YES;
			}
			else if ( isAlliance ){
				_attackingInStrand = NO;
			}
		}
		
		// Horde is defending!
		if ( [[nodeController nodesWithinDistance: 5000.0f NodeIDs:hordeNodes position:playerPosition] count] > 0 ){
			PGLog(@"[PvP] Horde is defending in strand!");
			if ( isHorde ){
				_attackingInStrand = NO;
			}
			else if ( isAlliance ){
				_attackingInStrand = YES;
			}
		}*/
		
		NSArray *antipersonnelCannons = [mobController mobsWithEntryID:StrandAntipersonnelCannon];
		
		if ( [antipersonnelCannons count] > 0 ){
			BOOL foundFriendly = NO, foundHostile = NO;
			for ( Mob *mob in antipersonnelCannons ){
				
				int faction = [mob factionTemplate];
				BOOL isHostile = [playerController isHostileWithFaction: faction];
				//PGLog(@"[PvP] Faction %d (%d) of Mob %@", faction, isHostile, mob);
				
				if ( isHostile ){
					foundHostile = YES;
				}
				else if ( !isHostile ){
					foundFriendly = YES;
				}
			}
			
			if ( foundHostile && foundFriendly ){
				PGLog(@"[PvP] New round for Strand! Found hostile and friendly! Were we attacking last round? %d", _attackingInStrand);
				_attackingInStrand = _attackingInStrand ? NO : YES;
			}
			else if ( foundHostile ){
				_attackingInStrand = YES;
				PGLog(@"[PvP] We're attacking in strand!");
			}
			else if ( foundFriendly ){
				_attackingInStrand = NO;
				PGLog(@"[PvP] We're defending in strand!");
			}
		}
		// If we don't see anything, then we're attacking!
		else{
			_attackingInStrand = YES;
			PGLog(@"[PvP] We're attacking in strand!");
		}
		
		// Check to see if we're on the boat!
		if ( _attackingInStrand && [playerController isOnBoatInStrand]){
			_strandDelay = YES;
			PGLog(@"[PvP] We're on a boat so lets delay our movement until it settles!");
		}
	}
}

// This little guy controls most of our PvP functions!
- (void)pvpMonitor: (NSTimer*)timer{
	if(!self.isPvPing)						return;
	if(![playerController playerIsValid:self])   return;
	
	BOOL isPlayerInBG = [playerController isInBG:[playerController zone]];
	Player *player = [playerController player];
	
	// Player just left the BG!
	if ( _pvpIsInBG && !isPlayerInBG ){
		_pvpIsInBG = NO;
		
		PGLog(@"[PvP] Player has left the battleground...");
		
		// Stop the bot! (this could be triggered by our marks check, but of course someone could have maxed marks)
		if ( self.isBotting ){
			[self stopBot: nil];
		}
		
		[movementController pauseMovement];
		
		// Only requeue if we're PvPing!
		if ( self.isPvPing ){

			// check for deserter
			BOOL hasDeserter = NO;
			if( [player isValid] && [auraController unit: player hasAura: DeserterSpellID] ) {
				hasDeserter = YES;
			}
			
			if( [controller sendGrowlNotifications] && [GrowlApplicationBridge isGrowlInstalled] && [GrowlApplicationBridge isGrowlRunning]) {
				// [GrowlApplicationBridge setGrowlDelegate: @""];
				[GrowlApplicationBridge notifyWithTitle: [NSString stringWithFormat: @"Battleground Complete"]
											description: (hasDeserter ? @"Waiting for Deserter to fade." : @"Will re-queue in 15 seconds.")
									   notificationName: @"BattlegroundLeave"
											   iconData: (([controller reactMaskForFaction: [player factionTemplate]] & 0x2) ? [[NSImage imageNamed: @"BannerAlliance"] TIFFRepresentation] : [[NSImage imageNamed: @"BannerHorde"] TIFFRepresentation])
											   priority: 0
											   isSticky: NO
										   clickContext: nil];             
			}
			if(hasDeserter) {
				PGLog(@"[PvP] Deserter! Waiting for deserter to go away :(");
				[controller setCurrentStatus: @"PvP: Waiting for Deserter to fade..."];
				[self performSelector: @selector(pvpQueueBattleground) withObject: nil afterDelay: 10.0];
				return;
			}
			
			// Requeue after 15 seconds (to account for some crappy computers)
			[controller setCurrentStatus: @"PvP: Re-queueing for BG in 15 seconds..."];
			[self performSelector: @selector(pvpQueueBattleground) withObject: nil afterDelay: 15.0f];
		}
	}
	
	// Player just joined the BG!
	else if ( !_pvpIsInBG && isPlayerInBG ){
		_pvpIsInBG = YES;
		
		// cancel the PvP checks
		[NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(pvpCheck) object: nil];
		
		if ( self.isPvPing ){
			_pvpMarks = [itemController pvpMarks];
			
			if( [controller sendGrowlNotifications] && [GrowlApplicationBridge isGrowlInstalled] && [GrowlApplicationBridge isGrowlRunning]) {
				// [GrowlApplicationBridge setGrowlDelegate: @""];
				[GrowlApplicationBridge notifyWithTitle: [NSString stringWithFormat: @"Battleground Entered"]
											description: [NSString stringWithFormat: @"Starting bot in 5 seconds."]
									   notificationName: @"BattlegroundEnter"
											   iconData: (([controller reactMaskForFaction: [[playerController player] factionTemplate]] & 0x2) ? [[NSImage imageNamed: @"BannerAlliance"] TIFFRepresentation] : [[NSImage imageNamed: @"BannerHorde"] TIFFRepresentation])
											   priority: 0
											   isSticky: NO
										   clickContext: nil];             
			}
			
			// Start bot after 5 seconds!
			PGLog(@"[PvP] PvP environment valid. Starting bot in 5 seconds...");
			[controller setCurrentStatus: @"PvP: Starting Bot in 5 seconds..."];
			[self performSelector: @selector(startBotForPvP) withObject: nil afterDelay: 5.0f];
		}
	}
	
	
	// We can do some checks in here amirite?
	if ( _pvpIsInBG && isPlayerInBG ){
		
		if ( self.isPvPing ){
			// Play warning!
			if( self.pvpPlayWarning ) {
				if( [auraController unit: player hasAura: IdleSpellID] || [auraController unit: player hasAura: InactiveSpellID]) {
					[[NSSound soundNamed: @"alarm"] play];
					PGLog(@"[PvP] Idle/Inactive debuff detected!");
				}
			}
			
			// Leave BG?
			if( [auraController unit: player hasAura: InactiveSpellID] && self.pvpLeaveInactive ) {
				// leave the battleground
				PGLog(@"[PvP] Leaving battleground due to Inactive debuff.");
				
				[macroController useMacroOrSendCmd:@"LeaveBattlefield"];
			}
		}
		
		// Check to see if we have been awarded a mark!  If so the BG has closed!
		if ( _pvpMarks > 0 && [itemController pvpMarks] > _pvpMarks ){
			
			// Lets stop botting!
			if ( self.isBotting ){
				[self stopBot: nil];
				
				PGLog(@"[PvP] BG has ended, botting stopped. %d > %d", [itemController pvpMarks], _pvpMarks );
				[controller setCurrentStatus: @"PvP: BG has ended, botting stopped."];
			}
		}
	}
	
	if ( !isPlayerInBG && self.isBotting ){
		PGLog(@"WE SHOULD NEVER BE HERE! Why are we botting outside of the BG?!?!?!");
	}
}

- (void)startBotForPvP{
	// Make sure player is valid, sometimes it takes longer than 5 seconds :(
	if ( self.isPvPing ){
		if ( ![playerController playerIsValid:self] ){
			[self performSelector: @selector(startBotForPvP) withObject: nil afterDelay: 1.0f];
			return;
		}
	
		[self startBot:nil];
	}
}

- (void)pvpQueueRetry{
	if ( [playerController battlegroundStatus] != BGNone ){
		return;
	}
	
	PGLog(@"[PvP] Still not queued, trying again!");
	[macroController useMacroOrSendCmd:@"JoinBattlefield"];
	
	float nextCheck = SSRandomFloatBetween(1.0f, 5.0f);
	[self performSelector: @selector(pvpQueueRetry) withObject: nil afterDelay:nextCheck];
}

- (void)pvpQueueBattleground{
	if(!self.isPvPing)										return;
	if(![playerController playerIsValid:self])				return;
	if ([playerController isInBG:[playerController zone]])	return;
	
	if ( [playerController battlegroundStatus] == BGQueued ){
		PGLog(@"[PvP] Already queued, no need to try again!");
		return;
	}
	
	// check for deserter
    if( [auraController unit: [playerController player] hasAura: DeserterSpellID] ) {
		[controller setCurrentStatus: @"PvP: Waiting for deserter to fade..."];
		
		// Will jump once every 1-3 minutes
        if(self.pvpCheckCount++ >= 4) {
            self.pvpCheckCount = 0;
            if(![controller isWoWChatBoxOpen]) {
				[self noAFK];
			}
        }
		
		// make sure pvpCheck isn't going - it shouldn't be
		[NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(pvpCheck) object: nil];
		
		float nextQueueAttempt = SSRandomFloatBetween(15.0f, 45.0f);
		[self performSelector: @selector(pvpQueueBattleground) withObject: nil afterDelay:nextQueueAttempt];
        return;
    }
	
	PGLog(@"[PvP] Queueing...");
	
	// Open PvP screen
	[chatController sendKeySequence:[NSString stringWithFormat: @"%c", 'h']];
	usleep(10000);
	
	// Lets queue!
	[macroController useMacroOrSendCmd:@"JoinBattlefield"];
	        
	[self noAFK];
	self.pvpCheckCount = 0;
	[controller setCurrentStatus: @"PvP: Waiting to join Battleground."];
	[self pvpCheck];
	
	// To account for sometimes the queue failing, lets try to join after minute or two just in case?
	float nextCheck = SSRandomFloatBetween(60.0f, 120.0f);
	[self performSelector: @selector(pvpQueueBattleground) withObject: nil afterDelay:nextCheck];
	
	// try to queue again in case it failed!
	[self performSelector: @selector(pvpQueueRetry) withObject: nil afterDelay:1.0f];
}

// this will keep us from going afk
- (void)pvpCheck {
	if(![playerController playerIsValid:self])   return;
	
    if(self.isPvPing) {
		if ( [playerController isInBG:[playerController zone]] ){
			return;
		}
		
        [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(pvpCheck) object: nil];
        
		// Will jump once every minute
        if(self.pvpCheckCount++ >= 60) {
            self.pvpCheckCount = 0;
            [self noAFK];
        }
		
        [self performSelector: @selector(pvpCheck) withObject: nil afterDelay: 1.0f];
    }
}

- (NSString*)pvpButtonTitle {
    if(self.isPvPing)   return @"Stop PvP";
    else                return @"Start PvP";
}

- (void)pvpStop {
    [self stopBot: nil];
    
    self.isPvPing = NO;
    self.pvpLeaveInactive = NO;
    self.pvpPlayWarning = NO;
    self.pvpCheckCount = 0;
	
	[_pvpTimer invalidate]; _pvpTimer = nil;
	
    PGLog(@"[PvP] Stopped.");
    
    [self willChangeValueForKey: @"pvpButtonTitle"];
    [self didChangeValueForKey: @"pvpButtonTitle"];
}

- (void)pvpStart {
    Player *player = [playerController player];
    if(![player isValid]) return;
	
	// If we're not PvPing - we want to start!
    if(!self.isPvPing) {
		[chatController sendKeySequence:[NSString stringWithFormat: @"%c", 'h']];

        if(([controller reactMaskForFaction: [player factionTemplate]] & 0x2)) {
            [pvpBannerImage setImage: [NSImage imageNamed: @"BannerAlliance"]];
        } else {
            [pvpBannerImage setImage: [NSImage imageNamed: @"BannerHorde"]];
        }
        
        [NSApp beginSheet: pvpBMSelectPanel
           modalForWindow: [self.view window]
            modalDelegate: self
           didEndSelector: @selector(pvpSheetDidEnd: returnCode: contextInfo:)
              contextInfo: nil];
        return;
    }
	
	// Reset our start date!
	self.startDate = [[NSDate date] retain];
	
	// Close the PvP window!
	[chatController sendKeySequence:[NSString stringWithFormat: @"%c", 'h']];
	
    self.pvpCheckCount = 0;
    self.pvpPlayWarning = [pvpPlayWarningCheckbox state];
    self.pvpLeaveInactive = [pvpLeaveInactiveCheckbox state];
    
    // off we go...?
    PGLog(@"[PvP] Starting...");
	[self pvpQueueBattleground];
	
	// Start our monitor!
	_pvpIsInBG = NO;
	_pvpTimer = [NSTimer scheduledTimerWithTimeInterval: 1.0f target: self selector: @selector(pvpMonitor:) userInfo: nil repeats: YES];
    
    [self willChangeValueForKey: @"pvpButtonTitle"];
    [self didChangeValueForKey: @"pvpButtonTitle"];
}

- (IBAction)pvpStartStop: (id)sender {
    if(self.isPvPing) {
        [self pvpStop];
    } else {
        [self pvpStart];
    }
}

- (void)pvpSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo {
    [pvpBMSelectPanel orderOut: nil];

    if(returnCode == NSCancelButton) {
		self.isPvPing = NO;
        return;
    }
    
    if(returnCode == NSOKButton) {
		self.isPvPing = YES;
        [self pvpStart];
    }
}

- (IBAction)pvpBMSelectAction: (id)sender {
    [NSApp endSheet: pvpBMSelectPanel returnCode: [sender tag]];
}

- (IBAction)pvpTestWarning: (id)sender {
    [[NSSound soundNamed: @"alarm"] play];
}

- (void)logOutWithMessage:(NSString*)message{
	
	PGLog(@"[Bot] %@", message);
	[self logOut];
	
	// sleep a bit before we update our status
	usleep(500000);
	[self updateStatus: [NSString stringWithFormat:@"Bot: %@", message]];
}

#pragma mark Timers

- (void)logOutTimer: (NSTimer*)timer {
	if ( !self.isBotting )
		PGLog(@"[Bot] We should never be here!!");
	
	BOOL logOutNow = NO;
	NSString *logMessage = nil;
	
	// check for full inventory
	if ( [logOutOnFullInventoryCheckbox state] && [itemController arePlayerBagsFull] ){
		logOutNow = YES;
		logMessage = @"Inventory full, closing game";
	}
	
	// check for timer
	if ( [logOutOnTimerExpireCheckbox state] && self.startDate ){
		float hours = [logOutAfterRunningTextField floatValue];
		NSDate *stopDate = [[NSDate alloc] initWithTimeInterval:hours * 60 * 60 sinceDate:self.startDate];
		
		// check to see which date is earlier
		if ( [stopDate earlierDate: [NSDate date] ] == stopDate ){
			logOutNow = YES;
			logMessage = [NSString stringWithFormat:@"Timer expired after %0.2f hours! Logging out!", hours];
		}
	}
	
	// check durability
	if ( [logOutOnBrokenItemsCheckbox state] ){
		float averageDurability = [itemController averageWearableDurability];
		float durabilityPercentage = [logOutAfterRunningTextField floatValue];
		
		if ( averageDurability > 0 && averageDurability < durabilityPercentage ){
			logOutNow = YES;
			logMessage = [NSString stringWithFormat:@"Item durability has reached %02.f, logging out!", averageDurability];
		}
	}
	
	// time to stop botting + log!
	if ( logOutNow ){
		[self logOutWithMessage:logMessage];
	}
}

// called every 30 seconds
- (void)afkTimer: (NSTimer*)timer {
	
	// don't need this if we're botting since we're doing things!
	if ( self.isBotting || ![playerController playerIsValid] )
		return;
	
	//PGLog(@"[AFK] Attempt: %d", _afkTimerCounter);
	
	
	if ( [antiAFKButton state] ){
		_afkTimerCounter++;
		
		// then we are at 4 minutes
		if ( _afkTimerCounter > 8 ){

			[self noAFK];
			
			_afkTimerCounter = 0;
		}
	}
}

// call this to prevent afk!
- (void)noAFK{
	// move backward!
	if ( _lastPressedWasForward ){
		[movementController moveBackwardStop];
		_lastPressedWasForward = NO;
		//PGLog(@"[AFK] Moving backward!");
	}
	// move forward!
	else{
		[movementController moveForwardStop];
		_lastPressedWasForward = YES;
		//PGLog(@"[AFK] Moving forward!");
	}
}

- (void)wgTimer: (NSTimer*)timer {
	
	// WG zone ID: 4197
	if ( [autoJoinWG state] && ![playerController isDead] && [playerController zone] == 4197 && [playerController playerIsValid] ){
		
		NSDate *currentTime = [NSDate date];
		
		// then we are w/in the first hour after we've done a WG!  Let's leave party!
		if ( _dateWGEnded && [currentTime timeIntervalSinceDate: _dateWGEnded] < 3600 ){
			// check to see if they are in a party - and leave!
			UInt32 offset = [offsetController offset:@"PARTY_LEADER_PTR"];
			UInt64 guid = 0;
			if ( [[controller wowMemoryAccess] loadDataForObject: self atAddress: offset Buffer: (Byte *)&guid BufLength: sizeof(guid)] && guid ){
				
				[macroController useMacroOrSendCmd:@"LeaveParty"];
				PGLog(@"[Bot] Player is in party leaving!");				
			}
			
			PGLog(@"[Bot] Leaving party anyways - there a leader? 0x%qX", guid);
			[macroController useMacroOrSendCmd:@"LeaveParty"];
		}
		
		// only autojoin if it's 2 hours+ after a WG end
		if ( _dateWGEnded && [currentTime timeIntervalSinceDate: _dateWGEnded] <= 7200 ){
			PGLog(@"[Bot] Not autojoing WG since it's been %0.2f seconds", [currentTime timeIntervalSinceDate: _dateWGEnded]);
			return;
		}
		
		// should we auto accept quests too? o.O
		
		// click the button!
		[macroController useMacroOrSendCmd:@"ClickFirstButton"];
		PGLog(@"[Bot] Autojoining WG!  Seconds since last WG: %0.2f", [currentTime timeIntervalSinceDate: _dateWGEnded]);
		
		// check how many marks they have (if it went up, we need to leave the group)!
		Item *item = [itemController itemForID:[NSNumber numberWithInt:43589]];
		if ( item && [item isValid] ){
			
			// it's never been set - /cry - lets set it!
			if ( _lastNumWGMarks == 0 ){
				_lastNumWGMarks = [item count];
				PGLog(@"[Bot] Setting wintegrasp mark counter to %d", _lastNumWGMarks);
			}
			
			// the player has more!
			if ( _lastNumWGMarks != [item count] ){
				_lastNumWGMarks = [item count];
				
				PGLog(@"[Bot] Wintergrasp over you now have %d marks! Leaving group!", _lastNumWGMarks);
				[macroController useMacroOrSendCmd:@"LeaveParty"];
				
				// update our time
				PGLog(@"[Bot] It's been %0.2f:: opens seconds since we were last given marks!", [currentTime timeIntervalSinceDate: _dateWGEnded]);
				[_dateWGEnded release]; _dateWGEnded = nil;
				_dateWGEnded = [[NSDate date] retain];
			}
		}
	}
}

- (BOOL)performAction: (int32_t) actionID{
	MemoryAccess *memory = [controller wowMemoryAccess];
	
	if ( !memory )
		return NO;
	
	UInt32 oldActionID = 0;
	UInt32 cooldown = [controller refreshDelay]*2;
	KeyCombo hotkey = [shortcutRecorder keyCombo];
	_currentHotkeyModifier = hotkey.flags;
	_currentHotkey = hotkey.code;
	
	// save the old spell + write the new one
	[memory loadDataForObject: self atAddress: ([offsetController offset:@"HOTBAR_BASE_STATIC"] + BAR6_OFFSET) Buffer: (Byte *)&oldActionID BufLength: sizeof(oldActionID)];
	[memory saveDataForAddress: ([offsetController offset:@"HOTBAR_BASE_STATIC"] + BAR6_OFFSET) Buffer: (Byte *)&actionID BufLength: sizeof(actionID)];
	
	// write gibberish to the error location
	char string[3] = {'_', '_', '\0'};
	[[controller wowMemoryAccess] saveDataForAddress: [offsetController offset:@"LAST_RED_ERROR_MESSAGE"] Buffer: (Byte *)&string BufLength:sizeof(string)];
	
	// wow needs time to process the spell change
	usleep(cooldown);

	// then post keydown if the chat box is not open
	if ( ![controller isWoWChatBoxOpen] || (_currentHotkey == kVK_F13) ) {
		[chatController pressHotkey: _currentHotkey withModifier: _currentHotkeyModifier];
		_lastSpellCastGameTime = [playerController currentTime];
		
		// make sure it was a spell and not an item/macro
		if ( !((USE_ITEM_MASK & actionID) || (USE_MACRO_MASK & actionID)) ){
			_lastSpellCast = actionID;
		}
		else {
			_lastSpellCast = 0;
		}
	}
	
	// wow needs time to process the spell change before we change it back
	usleep(cooldown*2);
	
	// then save our old action back
	[memory saveDataForAddress: ([offsetController offset:@"HOTBAR_BASE_STATIC"]+BAR6_OFFSET) Buffer: (Byte *)&oldActionID BufLength: sizeof(oldActionID)];
	
	// We don't want to check lastAttemptedActionID if it's not a spell!
	BOOL wasSpellCast = YES;
	if ( (USE_ITEM_MASK & actionID) || (USE_MACRO_MASK & actionID) ){
		wasSpellCast = NO;
	}
	
	// give WoW time to write to memory in case the spell didn't cast
	usleep(cooldown);
	
	_lastActionTime = [playerController currentTime];
	
	BOOL errorFound = NO;
	if ( ![[playerController lastErrorMessage] isEqualToString:@"__"] ){
		errorFound = YES;
	}
	
	// check for an error
	 if ( ( wasSpellCast && [spellController lastAttemptedActionID] == actionID ) || errorFound ){
		
		int lastErrorMessage = [self errorValue:[playerController lastErrorMessage]];
		 _lastActionErrorCode = lastErrorMessage;
		 PGLog(@"[Bot] Spell %d didn't cast(%d): %@", actionID, lastErrorMessage, [playerController lastErrorMessage] );

		 // do something?
		 if ( lastErrorMessage == ErrSpellNot_Ready){
			 [[NSNotificationCenter defaultCenter] postNotificationName: ErrorSpellNotReady object: nil];	
		 }
		 else if ( lastErrorMessage == ErrTargetNotInLOS ){
			 [[NSNotificationCenter defaultCenter] postNotificationName: ErrorTargetNotInLOS object: nil];	
		 }
		 else if ( lastErrorMessage == ErrInvalidTarget ){
			 [[NSNotificationCenter defaultCenter] postNotificationName: ErrorInvalidTarget object: nil];
		 }
		 else if ( lastErrorMessage == ErrTargetOutRange ){
			 [[NSNotificationCenter defaultCenter] postNotificationName: ErrorOutOfRange object: nil];
		 }
		 else if ( lastErrorMessage == ErrCantAttackMounted || lastErrorMessage == ErrYouAreMounted ){
			 if ( ![playerController isOnGround] ){
				 [movementController dismount];
			 }
		 }
		 // do we need to log out?
		 else if ( lastErrorMessage == ErrInventoryFull ){
			 if ( [logOutOnFullInventoryCheckbox state] )
				 [self logOutWithMessage:@"Inventory full, closing game"];
		 }
		 else if ( lastErrorMessage == ErrTargetNotInFrnt || lastErrorMessage == ErrWrng_Way ){
			 [[NSNotificationCenter defaultCenter] postNotificationName: ErrorTargetNotInFront object: nil];
		 }
		 
		 return lastErrorMessage;
	}

	return ErrNone;
}

- (int)errorValue: (NSString*) errorMessage{
	if (  [errorMessage isEqualToString: INV_FULL] ){
		return ErrInventoryFull;
	}
	else if ( [errorMessage isEqualToString:TARGET_LOS] ){
		return ErrTargetNotInLOS;
	}
	else if ( [errorMessage isEqualToString:SPELL_NOT_READY] ){
		return ErrSpellNotReady;
	}
	else if ( [errorMessage isEqualToString:TARGET_FRNT] ){
		return ErrTargetNotInFrnt;
	}
	else if ( [errorMessage isEqualToString:CANT_MOVE] ){
		return ErrCantMove;
	}
	else if ( [errorMessage isEqualToString:WRNG_WAY] ){
		return ErrWrng_Way;
	}
	else if ( [errorMessage isEqualToString:ATTACK_STUNNED] ){
		return ErrAttack_Stunned;
	}
	else if ( [errorMessage isEqualToString:NOT_YET] ){
		return ErrSpell_Cooldown;
	}
	else if ( [errorMessage isEqualToString:SPELL_NOT_READY2] ){
		return ErrSpellNot_Ready;
	}
	else if ( [errorMessage isEqualToString:NOT_RDY2] ){
		return ErrSpellNot_Ready;
	}
	else if ( [errorMessage isEqualToString:TARGET_RNGE] ){
		return ErrTargetOutRange;
	}
	else if ( [errorMessage isEqualToString:TARGET_RNGE2] ){
		return ErrTargetOutRange;
	}
	else if ( [errorMessage isEqualToString:INVALID_TARGET] || [errorMessage isEqualToString:CANT_ATTACK_TARGET] ){
		return ErrInvalidTarget;
	}
	else if ( [errorMessage isEqualToString:CANT_ATTACK_MOUNTED] ){
		return ErrCantAttackMounted;
	}
	else if ( [errorMessage isEqualToString:YOU_ARE_MOUNTED] ){
		return ErrYouAreMounted;
	}

	return ErrNotFound;
}


- (void)interactWithMob:(UInt32)entryID {
	Mob *mobToInteract = [mobController closestMobForInteraction:entryID];
	
	if([mobToInteract isValid]) {
		[self interactWithMouseoverGUID:[mobToInteract GUID]];
	}
}

- (void)interactWithNode:(UInt32)entryID {
	Node *nodeToInteract = [nodeController closestNodeForInteraction:entryID];
	
	if([nodeToInteract isValid]) {
		[self interactWithMouseoverGUID:[nodeToInteract GUID]];
	}
	else{
		PGLog(@"[Bot] Node %d not found, unable to interact", entryID);
	}
}

// This will set the GUID of the mouseover + trigger interact with mouseover!
- (BOOL)interactWithMouseoverGUID: (UInt64) guid{
	if ( [[controller wowMemoryAccess] saveDataForAddress: ([offsetController offset:@"TARGET_TABLE_STATIC"] + TARGET_MOUSEOVER) Buffer: (Byte *)&guid BufLength: sizeof(guid)] ){
		
		// wow needs time to process the change
		usleep([controller refreshDelay]);
		
		// Use our hotkey!
		KeyCombo hotkey = [mouseOverRecorder keyCombo];
		
		if ( hotkey.code < 0 ){
			return NO;
		}
		
		// Send out "interact with mouse over" keybinding!
		if(![controller isWoWChatBoxOpen] || (_currentHotkey == kVK_F13)) {
			[chatController pressHotkey: hotkey.code  withModifier: hotkey.flags];
			
			return YES;
		}
	}
	
	return NO;
}

// Simply will log us out!
- (void)logOut{
	
	if ( [logOutUseHearthstoneCheckbox state] && (_zoneBeforeHearth == -1) ){
		
		// Can only use if it's not on CD!
		if ( ![spellController isSpellOnCooldown:HearthStoneSpellID] ){
			
			_zoneBeforeHearth = [playerController zone];
			// Use our hearth
			UInt32 actionID = (USE_ITEM_MASK + HearthstoneItemID);
			[self performAction:actionID];
			
			// Kill bot + log out
			[self performSelector:@selector(logOut) withObject: nil afterDelay:25.0f];
			
			return;
		}
	}
	
	// The zones *should* be different
	if ( [logOutUseHearthstoneCheckbox state] ){
		if ( _zoneBeforeHearth != [playerController zone] ){
			PGLog(@"[Bot] Hearth successful from zone %d to %d", _zoneBeforeHearth, [playerController zone]);
		}
		else{
			PGLog(@"[Bot] Sorry hearth failed for some reason (on CD?), still closing WoW!");
		}
	}
	
	// Reset our variable in case the player fires up wow again later
	_zoneBeforeHearth = -1;
	
	// Stop the bot
	[self pvpStop];
	[self stopBot: nil];
	usleep(1000000);
		
	// Kill the process
	[controller killWOW];
}

// check if units are nearby
- (BOOL)scaryUnitsNearNode: (WoWObject*)node doMob:(BOOL)doMobCheck doFriendy:(BOOL)doFriendlyCheck doHostile:(BOOL)doHostileCheck{
	if ( doMobCheck ){
		PGLog(@"[Bot] Scanning nearby mobs within %0.2f of %@", _nodeIgnoreMobDistance, [node position]);
		NSArray *mobs = [mobController mobsWithinDistance: _nodeIgnoreMobDistance MobIDs:nil position:[node position] aliveOnly:YES];
		if ( [mobs count] ){
			PGLog(@"[Bot] There %@ %d scary mob(s) near the node, ignoring %@", ([mobs count] == 1) ? @"is" : @"are", [mobs count], node);
			return YES;
		}
	}
	if ( doFriendlyCheck ){
		if ( [playersController playerWithinRangeOfUnit: _nodeIgnoreFriendlyDistance Unit:(Unit*)node includeFriendly:YES includeHostile:NO] ){
			PGLog(@"[Bot] Friendly player(s) near node, ignoring %@", node);
			return YES;
		}
	}
	if ( doHostileCheck ){
		if ( [playersController playerWithinRangeOfUnit: _nodeIgnoreHostileDistance Unit:(Unit*)node includeFriendly:NO includeHostile:YES] ){
			PGLog(@"[Bot] Hostile player(s) near node, ignoring %@", node);
			return YES;
		}
	}
	
	return NO;
}

- (UInt8)isHotKeyInvalid{
	
	// We know it's not set if flags are 0 or code is -1 then it's not set!
	UInt8 flags = 0;

	// Check start/stop hotkey
	KeyCombo combo = [startstopRecorder keyCombo];
	if ( combo.code == -1 ){
		flags |= HotKeyStartStop;
	}
	
	// Check Interact with
	combo = [mouseOverRecorder keyCombo];
	if ( combo.code == -1 ){
		flags |= HotKeyInteractMouseover;
	}
	
	// Check Bottom Left Action Bar
	combo = [shortcutRecorder keyCombo];
	if ( combo.code == -1 ){
		flags |= HotKeyPrimary;
	}
	
	// Check Pet attack
	combo = [petAttackRecorder keyCombo];
	if ( combo.code == -1 ){
		flags |= HotKeyPetAttack;
	}
	
	return flags;	
}

- (char*)randomString: (int)maxLength{
	// generate a random string to write
	int i, len = SSRandomIntBetween(3,maxLength);
	char *string = (char*)malloc(len);
	char randomChar = 0;
    for (i = 0; i < len; i++) {
        while (YES) {
            randomChar = SSRandomIntBetween(0,128);
            if (((randomChar >= '0') && (randomChar <= '9')) || ((randomChar >= 'a') && (randomChar <= 'z'))) {
                string[i] = randomChar;
                break; // we found an alphanumeric character, move on
            }
        }
    }
	string[i] = '\0';
	
	return string;
}


- (IBAction)test2: (id)sender{
	/*
	Position *pos = [[Position alloc] initWithX: -4968.875 Y:-1208.304 Z:501.715];
	Position *playerPosition = [playerController position];
	
	PGLog(@"Distance: %0.2f", [pos distanceToPosition:playerPosition]);
	
	Position *newPos = [pos positionAtDistance:10.0f withDestination:playerPosition];
	
	PGLog(@"New pos: %@", newPos);
	
	[movementController setClickToMove:newPos andType:ctmWalkTo andGUID:0x0];
*/
}

- (int)CompareFactionHash: (int)hash1 withHash2:(int)hash2{	
	if ( hash1 == 0 || hash2 == 0 )
		return -1;
	
	UInt32 hashCheck1 = 0, hashCheck2 = 0;
	UInt32 check1 = 0, check2 = 0;
	int hashCompare = 0, hashIndex = 0, i = 0;
	//Byte *bHash1[0x40];
	//Byte *bHash2[0x40];
	
	MemoryAccess *memory = [controller wowMemoryAccess];
	//[memory loadDataForObject: self atAddress: hash1 Buffer: (Byte*)&bHash1 BufLength: sizeof(bHash1)];
	//[memory loadDataForObject: self atAddress: hash2 Buffer: (Byte*)&bHash2 BufLength: sizeof(bHash2)];
	
	// get the hash checks
	[memory loadDataForObject: self atAddress: hash1 + 0x4 Buffer: (Byte*)&hashCheck1 BufLength: sizeof(hashCheck1)];
	[memory loadDataForObject: self atAddress: hash2 + 0x4 Buffer: (Byte*)&hashCheck2 BufLength: sizeof(hashCheck2)];
	
	//bitwise compare of [bHash1+0x14] and [bHash2+0x0C]
	[memory loadDataForObject: self atAddress: hash1 + 0x14 Buffer: (Byte*)&check1 BufLength: sizeof(check1)];
	[memory loadDataForObject: self atAddress: hash2 + 0xC Buffer: (Byte*)&check2 BufLength: sizeof(check2)];
	if ( ( check1 & check2 ) != 0 )
		return 1;	// hostile
	
	hashIndex = 0x18;
	[memory loadDataForObject: self atAddress: hash1 + hashIndex Buffer: (Byte*)&hashCompare BufLength: sizeof(hashCompare)];
	if ( hashCompare != 0 ){
		for ( i = 0; i < 4; i++ ){
			if ( hashCompare == hashCheck2 )
				return 1; // hostile
			
			hashIndex += 4;
			[memory loadDataForObject: self atAddress: hash1 + hashIndex Buffer: (Byte*)&hashCompare BufLength: sizeof(hashCompare)];
			
			if ( hashCompare == 0 )
				break;
		}
	}
	
	//bitwise compare of [bHash1+0x10] and [bHash2+0x0C]
	[memory loadDataForObject: self atAddress: hash1 + 0x10 Buffer: (Byte*)&check1 BufLength: sizeof(check1)];
	[memory loadDataForObject: self atAddress: hash2 + 0xC Buffer: (Byte*)&check2 BufLength: sizeof(check2)];
	if ( ( check1 & check2 ) != 0 ){
		PGLog(@"friendly");
		return 4;	// friendly
	}
	
	hashIndex = 0x28;
	[memory loadDataForObject: self atAddress: hash1 + hashIndex Buffer: (Byte*)&hashCompare BufLength: sizeof(hashCompare)];
	if ( hashCompare != 0 ){
		for ( i = 0; i < 4; i++ ){
			if ( hashCompare == hashCheck2 ){
				PGLog(@"friendly2");
				return 4;	// friendly
			}
			
			hashIndex += 4;
			[memory loadDataForObject: self atAddress: hash1 + hashIndex Buffer: (Byte*)&hashCompare BufLength: sizeof(hashCompare)];
			
			if ( hashCompare == 0 )
				break;
		}
	}
	
	 //bitwise compare of [bHash2+0x10] and [bHash1+0x0C]
	[memory loadDataForObject: self atAddress: hash2 + 0x10 Buffer: (Byte*)&check1 BufLength: sizeof(check1)];
	[memory loadDataForObject: self atAddress: hash1 + 0xC Buffer: (Byte*)&check2 BufLength: sizeof(check2)];
	if ( ( check1 & check2 ) != 0 ){
		PGLog(@"friendly3");
		return 4;	// friendly
	}
	
	hashIndex = 0x28;
	[memory loadDataForObject: self atAddress: hash2 + hashIndex Buffer: (Byte*)&hashCompare BufLength: sizeof(hashCompare)];
	if ( hashCompare != 0 ){
		for ( i = 0; i < 4; i++ ){
			if ( hashCompare == hashCheck1 ){
				PGLog(@"friendly4");
				return 4;	// friendly
			}
				
			hashIndex += 4;
			[memory loadDataForObject: self atAddress: hash2 + hashIndex Buffer: (Byte*)&hashCompare BufLength: sizeof(hashCompare)];
			
			if ( hashCompare == 0 )
				break;
		}
	}
	
	return 3;	//neutral
}

- (IBAction)test: (id)sender{
	
	
	MemoryAccess *memory = [controller wowMemoryAccess];
	UInt32 factionPointer = 0, totalFactions = 0, startIndex = 0;
	[memory loadDataForObject: self atAddress: 0xD787C0 + 0x10 Buffer: (Byte*)&startIndex BufLength: sizeof(startIndex)];
	[memory loadDataForObject: self atAddress: 0xD787C0 + 0xC Buffer: (Byte*)&totalFactions BufLength: sizeof(totalFactions)];
	[memory loadDataForObject: self atAddress: 0xD787C0 + 0x20 Buffer: (Byte*)&factionPointer BufLength: sizeof(factionPointer)];
	
	
	UInt32 hash1, hash2;
	int faction1 = [[playerController player] factionTemplate];
	int faction2 = 3;
	
	
	GUID guid = [playerController targetID];
	
	Unit *unit = [mobController mobWithGUID:guid];
	if ( !unit ){
		// player?
		unit = [playersController playerWithGUID:guid];
	}
	
	if ( unit ){
		PGLog(@"We have a unit %@ with faction %d", unit, [unit factionTemplate]);
		faction2 = [unit factionTemplate];
	}
	
	if ( faction1 >= startIndex && faction1 < totalFactions && faction2 >= startIndex && faction2 < totalFactions ){
		hash1 = (factionPointer + ((faction1 - startIndex)*4));
		hash2 = (factionPointer + ((faction2 - startIndex)*4));
		
		PGLog(@"Hashes: 0x%X  0x%X", hash1, hash2);
		
		PGLog(@"Result of compare: %d", [self CompareFactionHash:hash1 withHash2:hash2]);
	}

	
	/*
	//[playerController isOnRightBoatInStrand];
	
	MemoryAccess *memory = [controller wowMemoryAccess];
	int v0=0,i=0,tmp=0,ptr=0;
	[memory loadDataForObject: self atAddress: 0x10E760C Buffer: (Byte*)&ptr BufLength: sizeof(ptr)];
	[memory loadDataForObject: self atAddress: ptr + 180 Buffer: (Byte*)&v0 BufLength: sizeof(v0)];
	
	if ( v0 & 1 || !v0 )
		v0 = 0;
	
	int type = 0;
	for ( i = 0; !(v0 & 1); ){
		[memory loadDataForObject: self atAddress: ptr + 172 Buffer: (Byte*)&tmp BufLength: sizeof(tmp)];
		[memory loadDataForObject: self atAddress: tmp + v0 + 4 Buffer: (Byte*)&v0 BufLength: sizeof(v0)];
		[memory loadDataForObject: self atAddress: v0 + 0x10 Buffer: (Byte*)&type BufLength: sizeof(type)];
		PGLog(@"[Test] Address: 0x%X %d", v0, type);
		if ( !v0 )
			break;
		++i;
	}
	
	PGLog(@"[Test] Total : %d", i);
	
	int v2=0, v3=0;
	[memory loadDataForObject: self atAddress: ptr + 12 Buffer: (Byte*)&v2 BufLength: sizeof(v2)];
	if ( v2 & 1 || !v2 )
		v2 = 0;
	v3 = 0;*/
	
	/*
	int v0; // eax@1
	int i; // edi@3
	int v2; // eax@6
	int v3; // esi@8
	int v4; // eax@12
	int v5; // eax@16
	int v6; // ebx@18
	
	v0 = *(_DWORD *)(dword_10E760C + 180);
	if ( v0 & 1 || !v0 )
		v0 = 0;
	for ( i = 0; !(v0 & 1); v0 = *(_DWORD *)(*(_DWORD *)(dword_10E760C + 172) + v0 + 4) )
	{
		if ( !v0 )
			break;
		++i;
	}
	v2 = *(_DWORD *)(dword_10E760C + 12);
	if ( v2 & 1 || !v2 )
		v2 = 0;
	v3 = 0;
LABEL_9:
	if ( !(v2 & 1) )
	{
		while ( v2 )
		{
			++v3;
			if ( v2 )
				v4 = *(_DWORD *)(dword_10E760C + 4) + v2;
			else
				v4 = dword_10E760C + 8;
			v2 = *(_DWORD *)(v4 + 4);
			if ( v2 & 1 )
			{
				v2 = 0;
			}
			else
			{
				if ( v2 )
					goto LABEL_9;
				v2 = 0;
			}
			if ( v2 & 1 )
				break;
		}
	}
	v5 = *(_DWORD *)(dword_10E760C + 56);
	if ( v5 & 1 || !v5 )
		v5 = 0;
	v6 = 0;
LABEL_19:
	if ( !(v5 & 1) )
	{
		while ( v5 )
		{
			++v6;
			v5 = *(_DWORD *)(*(_DWORD *)(dword_10E760C + 48) + v5 + 4);
			if ( v5 & 1 )
			{
				v5 = 0;
			}
			else
			{
				if ( v5 )
					goto LABEL_19;
				v5 = 0;
			}
			if ( v5 & 1 )
				break;
		}
	}
	sub_1214D0("Object manager list status:", 7);
	sub_122110("    Active objects:              %u objects (%u visible)", 7, v3);
	sub_122110("    Objects waiting to be freed: %u objects", 7, v6, i);
	return 1;
*/	
	
	
	
	
	
	
	
	
	
	
/*
	Position *pos = [[Position alloc] initWithX: -4968.875 Y:-1208.304 Z:501.715];
	Position *playerPosition = [playerController position];
	
	// this is where we want to face!
	float direction = [playerPosition angleTo:pos];
	
	PGLog(@"Angle to target: %0.2f", direction);
	[playerController setDirectionFacing:direction];
	*/
	//0-2pi. North is 0, west is pi/2, south is pi, east is 3pi/2.
	/*
	int quadrant = 0;
	
	if ( 0.0f < direction && direction <= M_PI/2.0f ){
		quadrant = 1;
	}
	else if ( M_PI/2.0f < direction && direction <= M_PI ){
		quadrant = 2;
	}
	else if ( M_PI < direction && direction <= (3*M_PI)/2.0f ){
		quadrant = 3;
	}
	else if ( (3.0f*M_PI)/2.0f < direction && direction <= 2*M_PI ){
		quadrant = 4;
	}*/
	
	/*
	
	float x, y;
	float closeness = 10.0f;
	
	// negative x
	if ( [pos xPosition] < 0.0f ){
		x = -1.0f * (cosf(direction) * closeness);
	}
	// positive x
	else{
		x = (cosf(direction) * closeness);
	}
	
	// negative y
	if ( [pos yPosition] < 0.0f ){
		y = -1.0f * (sinf(direction) * closeness);
	}
	// positive y
	else{
		y = (sinf(direction) * closeness);
	}
	
	Position *newPos = [[Position alloc] initWithX:([pos xPosition] + x) Y:([pos yPosition] + y) Z:[pos zPosition]];
	PGLog(@"Change in position: {%0.2f, %0.2f}", x, y);
	
	[movementController setClickToMove:newPos andType:ctmWalkTo andGUID:0x0];
	*/
		
	//[controller traverseNameList];
	/*

	PGLog(@"After  write:'%@'", [playerController lastErrorMessage]);
	NSString *lastErrorMessageAltered = [playerController lastErrorMessage];*/
	//free(string);

	
	//(BOOL)saveDataForAddress: (UInt32)address Buffer: (Byte *)DataBuffer BufLength: (vm_size_t)Bytes;
	
/*
	
	Position *playerPosition = [playerController position];
	Position *destination = [Position positionWithX:5486.823f Y:297.879f Z:147.4111];
	Position *pos = [destination positionAtDistance:15.0f withDestination:playerPosition];
	
	PGLog(@"10 yards from %@ is %@", destination, pos);
	//[movementController turnToward:pos];
	
	[movementController moveNearPosition:pos andCloseness:0.0f];
	
	
	
	*/
	
	
	
	/*if ( self.theCombatProfile == nil )
		self.theCombatProfile = [[combatProfilePopup selectedItem] representedObject];
	
	
	PGLog(@"Attack range: %0.2f", self.theCombatProfile.attackRange);
	PGLog(@"[Bot] Current best target: %@", [combatController findBestUnitToAttack]);*/
	
	

}

#define ACCOUNT_NAME_SEP	@"SET accountName \""
#define ACCOUNT_LIST_SEP	@"SET accountList \""
/*
 
SET accountName "myemail@hotmail.com"
SET accountList "!ACCOUNT1|ACCOUNT2|"
 */
- (IBAction)login: (id)sender{
	//LOGIN_STATE		this will be "login", "charselect", or "charcreate"
	//	note: it will stay in it's last state even if we are logged in + running around!
	
	//LOGIN_SELECTED_CHAR - we want to write the position to memory, the chosen won't change on screen, but it will log into that char!
	//	values: 0-max
	
	//LOGIN_TOTAL_CHARACTERS - obviously the total number of characters on the selection screen
	
	NSString *account = @"MyBNETAccount12312";
	NSString *password = @"My1337Password";
	NSString *accountList = @"!Accoun23t1|Accoun1t2|";
	
	
	
	// ***** GET THE PATH TO OUR CONFIG FILE
	NSString *configFilePath = [controller wowPath];
	// will be the case if wow is closed (lets go with the default option?)
	if ( [configFilePath length] == 0 ){
		[configFilePath release]; configFilePath = nil;
		configFilePath = @"/Applications/World of Warcraft/WTF/Config.wtf";
	}
	// we have a dir
	else{
		configFilePath = [configFilePath stringByDeletingLastPathComponent];
		configFilePath = [configFilePath stringByAppendingPathComponent: @"WTF/Config.wtf"];	
	}

	
	// ***** GET OUR CONFIG FILE DATA + BACK IT UP!
	NSString *configData = [[NSString alloc] initWithContentsOfFile:configFilePath];
	NSMutableString *newConfigFile = [NSMutableString string];
	NSMutableString *configFileBackup = [NSString stringWithFormat:@"%@.bak", configFilePath];
	
	NSFileManager *fileManager = [NSFileManager defaultManager];
	if ( ![fileManager fileExistsAtPath:configFilePath] || [configData length] == 0 ){
		PGLog(@"[Bot] Unable to find config file at path '%@'. Aborting.", configFilePath);
		return;
	}
	// should we create a backup file?
	if ( ![fileManager fileExistsAtPath:configFileBackup] ){
		if ( ![configData writeToFile:configFileBackup atomically:YES encoding:NSUnicodeStringEncoding error:nil] ){
			PGLog(@"[Bot] Unable to backup existing config file to '%@'. Aborting", configFileBackup);
			return;
		}
	}
	
	// if we get here we have a config file! And have backed it up!
	
	
	// Three conditions for information in this file:
	//	1. Account list and Account name are set
	//	2. Account list is set (when remember checkbox was once checked, but is no longer)
	//	3. Neither exist in config file
	if ( configData != nil ){
		
		NSScanner *scanner = [NSScanner scannerWithString: configData];
		
		BOOL accountNameFound = NO;
		BOOL accountListFound = NO;
		NSString *beforeAccountName = nil;
		NSString *beforeAccountList = nil;

        // get the account name?
		int scanSave = [scanner scanLocation];
		PGLog(@"Location: %d", [scanner scanLocation]);
        if([scanner scanUpToString: ACCOUNT_NAME_SEP intoString: &beforeAccountName] && [scanner scanString: ACCOUNT_NAME_SEP intoString: nil]) {
            NSString *newName = nil;
            if ( [scanner scanUpToString: @"\"" intoString: &newName] && newName && [newName length] ) { 
				//PGLog(@"Account name: %@", newName);
				accountNameFound = YES;
            }
        }
		
		// if the user doesn't have "remember" checked, the above search will fail, so lets reset to find the account list! (maybe?)
		if ( !accountNameFound ){
			[scanner setScanLocation: scanSave];
		}
		
		// get the account list
		scanSave = [scanner scanLocation];
		PGLog(@"Location: %d %d", [scanner scanLocation], [beforeAccountName length]);
        if ( [scanner scanUpToString: ACCOUNT_LIST_SEP intoString: &beforeAccountList] && [scanner scanString: ACCOUNT_LIST_SEP intoString: nil] ) {
            NSString *newName = nil;
            if ( [scanner scanUpToString: @"\"" intoString: &newName] && newName && [newName length] ) {
				//PGLog(@"Account list: %@", newName);
				accountListFound = YES;
            }
        }
		
		// reset the location, in case we have info after our login info + can add it back to the config file!
		if ( !accountListFound ){
			[scanner setScanLocation: scanSave];
		}
		PGLog(@"Location: %d %d", [scanner scanLocation], [beforeAccountList length]);
		// save what we have left in the scanner! There could be config data after our account name!
		NSString *endOfConfigFileData = [[scanner string]substringFromIndex:[scanner scanLocation]];
		
		// condition 1: we have an existing account! we need to replace it (and potentially an account list to add)
		if ( accountNameFound ){
			// add our new account name
			[newConfigFile appendString:beforeAccountName];
			[newConfigFile appendString:ACCOUNT_NAME_SEP];
			[newConfigFile appendString:account];
			[newConfigFile appendString:@"\""];
			
			// did we also have an account list to replace?
			if ( [accountList length] ){
				[newConfigFile appendString:@"\n"];
				[newConfigFile appendString:ACCOUNT_LIST_SEP];
				[newConfigFile appendString:accountList];
				[newConfigFile appendString:@"\""];
			}
		}
		
		// condition 2: only the account list was found, add the account name + potentially replace the account list
		else if ( accountListFound ){
			[newConfigFile appendString:beforeAccountList];
			[newConfigFile appendString:ACCOUNT_NAME_SEP];
			[newConfigFile appendString:account];
			[newConfigFile appendString:@"\""];
			
			if ( [accountList length] ){
				[newConfigFile appendString:@"\n"];
				[newConfigFile appendString:ACCOUNT_LIST_SEP];
				[newConfigFile appendString:accountList];
				[newConfigFile appendString:@"\""];
			}
		}
		
		// condition 3: nothing was found
		else{
			[newConfigFile appendString:beforeAccountList];
			[newConfigFile appendString:ACCOUNT_NAME_SEP];
			[newConfigFile appendString:account];
			[newConfigFile appendString:@"\""];
			
			if ( [accountList length] ){
				[newConfigFile appendString:@"\n"];
				[newConfigFile appendString:ACCOUNT_LIST_SEP];
				[newConfigFile appendString:accountList];
				[newConfigFile appendString:@"\""];
			}
		}
		
		// only add data if we found an account name or list!
		if ( ( accountListFound || accountNameFound ) && [endOfConfigFileData length] ){
			[newConfigFile appendString:endOfConfigFileData];
		}

	}

	// write our new config file!
	[newConfigFile writeToFile:configFileBackup atomically:YES encoding:NSUnicodeStringEncoding error:nil];
	PGLog(@"[Bot] New config file written to '%@'", configFilePath);
	
	// make sure wow is open
	if ( [controller isWoWOpen] ){
		
		[chatController sendKeySequence:account];
		usleep(50000);
		[chatController sendKeySequence:password];	   
		
	}
}

#define SimonAuraBlueEntryID	185872
#define SimonAuraYellowEntryID	185875
#define SimonAuraRedEntryID		185874
#define SimonAuraGreenEntryID	185873
//#define SimonRelicDischarger	185894
#define SimonApexisRelic		185890

#define BlueCluster				185828
#define GreenCluster			185830
#define RedCluster				185831
#define YellowCluster			185829

- (IBAction)doTheRelicEmanation: (id)sender{
	
	
	// interact with discharger
	// wait 1.2 seconds
	// send macro or command to click!
	
	// MUST rescan after each time, the object change!!
	
	/*Node *green = [nodeController closestNode:SimonAuraGreenEntryID];
	Node *red = [nodeController closestNode:SimonAuraRedEntryID];
	Node *blue = [nodeController closestNode:SimonAuraBlueEntryID];
	Node *yellow = [nodeController closestNode:SimonAuraYellowEntryID];
	
	if ( green == nil ){
		[self performSelector:@selector(doTheRelicEmanation:) withObject:nil afterDelay:0.1f];
		return;
	}
	
	PGLog(@"Green: %@", green);
	PGLog(@"Red: %@", red);
	PGLog(@"Blue: %@", blue);
	PGLog(@"Yellow: %@", yellow);
	
	//NSArray *objects = [NSArray arrayWithObjects:green, red, blue, yellow, nil];
	
	//[memoryViewController monitorObjects:objects];
	
	
	green = [nodeController closestNode:BlueCluster];
	red = [nodeController closestNode:GreenCluster];
	blue = [nodeController closestNode:RedCluster];
	yellow = [nodeController closestNode:YellowCluster];
	
	
	[self monitorObject: green];
	[self monitorObject: red];
	[self monitorObject: blue];
	[self monitorObject: yellow];*/
	
	/*[memoryViewController monitorObject:green];
	[memoryViewController monitorObject:red];
	[memoryViewController monitorObject:blue];
	[memoryViewController monitorObject:yellow];*/
	//[self performSelector:@selector(doTheRelicEmanation:) withObject:nil afterDelay:0.1];
}

- (void)monitorObject: (WoWObject*)obj{
	
	
	UInt32 addr1 = [obj baseAddress] + 0x1F8;
	UInt32 addr2 = [obj baseAddress] + 0x230;
	UInt32 addr3 = [obj baseAddress] + 0x250;
	UInt32 addr4 = [obj baseAddress] + 0x260;
	
	MemoryAccess *memory = [controller wowMemoryAccess];
    if(memory) {
        UInt16 value1 = 0, value2 = 0, value3 = 0, value4 = 0;
        [memory loadDataForObject: self atAddress: addr1 Buffer: (Byte *)&value1 BufLength: sizeof(value1)];
		[memory loadDataForObject: self atAddress: addr2 Buffer: (Byte *)&value2 BufLength: sizeof(value2)];
		[memory loadDataForObject: self atAddress: addr3 Buffer: (Byte *)&value3 BufLength: sizeof(value3)];
		[memory loadDataForObject: self atAddress: addr4 Buffer: (Byte *)&value4 BufLength: sizeof(value4)];

		PGLog(@"%d %d %d %d %@", value1, value2, value3, value4, obj);
	}
	
	
	if ( [obj isValid] ){
		[self performSelector:@selector(monitorObject:) withObject:obj afterDelay:0.1f];
	}
	else{
		PGLog(@"%@ is no longer valid...", obj);
	}
	
}

@end

