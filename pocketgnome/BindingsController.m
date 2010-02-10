//
//  BindingsController.m
//  Pocket Gnome
//
//  Created by Josh on 1/28/10.
//  Copyright 2010 Savory Software, LLC. All rights reserved.
//

#import "BindingsController.h"

#import "Controller.h"
#import "PlayerDataController.h"
#import "ChatController.h"
#import "BotController.h"
#import "OffsetController.h"

#import "MemoryAccess.h"

#import "Offsets.h"
#import <Carbon/Carbon.h>

@interface BindingsController (Internal)
- (void)getKeyBindings;
- (void)convertToAscii;
- (void)mapBindingsToKeys;
@end

@implementation BindingsController

- (id) init{
    self = [super init];
    if (self != nil) {
		
		_guid = 0x0;
		
		// invalidate all key bindings
		_primaryActionOffset = -1;
		_primaryActionCode = -1;
		_primaryActionModifier = -1;
		_petAttackActionOffset = -1;
		_petAttackActionCode = -1;
		_petAttackActionModifier = -1;
		_interactMouseoverActionOffset = -1;
		_interactMouseoverActionCode = -1;
		_interactMouseoverActionModifier = -1;
		
		// might move this to a plist eventually once I have all of them
		_commandToAscii = [[NSDictionary dictionaryWithObjectsAndKeys:
							[NSNumber numberWithInt:kVK_F1]					,@"f1",
							[NSNumber numberWithInt:kVK_Shift]				,@"shift",
							[NSNumber numberWithInt:kVK_F2]					,@"f2",
							[NSNumber numberWithInt:kVK_Space]				,@"space",			
							[NSNumber numberWithInt:kVK_Control]			,@"ctrl",				
							[NSNumber numberWithInt:kVK_F3]					,@"f3",				
							[NSNumber numberWithInt:-1]						,@"button2",			
							[NSNumber numberWithInt:-1]						,@"insert",			
							[NSNumber numberWithInt:kVK_F4]					,@"f4",				
							[NSNumber numberWithInt:-1]						,@"mousewheeldown",	
							[NSNumber numberWithInt:kVK_F5]					,@"f5",				
							[NSNumber numberWithInt:kVK_F8]					,@"f8",				
							[NSNumber numberWithInt:kVK_ANSI_Keypad1]		,@"numpad1",			
							[NSNumber numberWithInt:kVK_F9]					,@"f9",				
							[NSNumber numberWithInt:kVK_ANSI_Keypad4]		,@"numpad4",			
							[NSNumber numberWithInt:kVK_ANSI_Keypad7]		,@"numpad7",			
							[NSNumber numberWithInt:kVK_F7]					,@"f7",				
							[NSNumber numberWithInt:kVK_Option]				,@"alt",				
							[NSNumber numberWithInt:kVK_ANSI_KeypadPlus]	,@"numpadplus",		
							[NSNumber numberWithInt:-1]						,@"mousewheelup",		
							[NSNumber numberWithInt:kVK_PageDown]			,@"pagedown",				
							[NSNumber numberWithInt:kVK_ANSI_KeypadClear]	,@"numlock",			
							[NSNumber numberWithInt:-1]						,@"button3",			
							[NSNumber numberWithInt:kUpArrowCharCode]		,@"up",				
							[NSNumber numberWithInt:kVK_ANSI_Keypad2]		,@"numpad2",			
							[NSNumber numberWithInt:kVK_ANSI_Keypad5]		,@"numpad5",			
							[NSNumber numberWithInt:kVK_ANSI_Keypad8]		,@"numpad8",			
							[NSNumber numberWithInt:kVK_End]				,@"end",				
							[NSNumber numberWithInt:kVK_Tab]				,@"tab",				
							[NSNumber numberWithInt:kVK_DownArrow]			,@"down",				
							[NSNumber numberWithInt:kVK_ANSI_KeypadDivide]	,@"numpaddivide",		
							[NSNumber numberWithInt:-1]						,@"button1",			
							[NSNumber numberWithInt:-1]						,@"button4",	
							[NSNumber numberWithInt:-1]						,@"button5",
							//[NSNumber numberWithInt:-1]						,@"backspace",
							[NSNumber numberWithInt:kVK_Delete]				,@"delete",			
							[NSNumber numberWithInt:kVK_ANSI_Keypad0]		,@"numpad0",			
							[NSNumber numberWithInt:kVK_ANSI_Keypad3]		,@"numpad3",			
							[NSNumber numberWithInt:kVK_Return]				,@"enter",			
							[NSNumber numberWithInt:kVK_ANSI_Keypad6]		,@"numpad6",			
							[NSNumber numberWithInt:kVK_ANSI_Keypad9]		,@"numpad9",			
							[NSNumber numberWithInt:kVK_F6]					,@"f6",				
							[NSNumber numberWithInt:kVK_PageUp]				,@"pageup",			
							[NSNumber numberWithInt:kVK_Home]				,@"home",				
							[NSNumber numberWithInt:kVK_Escape]				,@"escape",			
							[NSNumber numberWithInt:kVK_ANSI_KeypadMinus]	,@"numpadminus",		
							[NSNumber numberWithInt:kVK_LeftArrow]			,@"left",				
							[NSNumber numberWithInt:kVK_F10]				,@"f10",				
							[NSNumber numberWithInt:kVK_F11]				,@"f11",				
							[NSNumber numberWithInt:kVK_RightArrow]			,@"right",			
							[NSNumber numberWithInt:kVK_F12]				,@"f12",		
							[NSNumber numberWithInt:kVK_F13]				,@"printscreen",	
							[NSNumber numberWithInt:kVK_F14]				,@"f14",	
							[NSNumber numberWithInt:kVK_F15]				,@"f15",	
							[NSNumber numberWithInt:kVK_F16]				,@"f16",	
							[NSNumber numberWithInt:kVK_F17]				,@"f17",	
							[NSNumber numberWithInt:kVK_F18]				,@"f18",	
							[NSNumber numberWithInt:kVK_F19]				,@"f19",	
							nil] retain];
						   
		_bindings = [[NSMutableDictionary dictionary] retain];
		_keyCodesWithCommands = [[NSMutableDictionary dictionary] retain];
		_bindingsToCodes = [[NSMutableDictionary dictionary] retain];
		
		// Notifications
		[[NSNotificationCenter defaultCenter] addObserver: self
												 selector: @selector(playerIsValid:) 
													 name: PlayerIsValidNotification 
												   object: nil];
		[[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(playerIsInvalid:) 
                                                     name: PlayerIsInvalidNotification 
                                                   object: nil];
    }
    return self;
}

- (void) dealloc{
	[_bindings release]; _bindings = nil;
	[_keyCodesWithCommands release]; _keyCodesWithCommands = nil;
	[_commandToAscii release]; _commandToAscii = nil;
	[_bindingsToCodes release]; _bindingsToCodes = nil;
    [super dealloc];
}

#pragma mark Notifications

- (void)playerIsValid: (NSNotification*)not {
	[self getKeyBindings];
}

- (void)playerIsInvalid: (NSNotification*)not {
	[_bindings removeAllObjects];
	[_keyCodesWithCommands removeAllObjects];
	[_bindingsToCodes removeAllObjects];
}

#pragma mark Key Bindings Scanner

- (void)reloadBindings{
	[self getKeyBindings];
}

typedef struct WoWBinding {
    UInt32 nextBinding;		// 0x0
	UInt32 unknown1;		// 0x4	pointer to a list of something
	UInt32 keyPointer;		// 0x8
	UInt32 unknown2;		// 0xC	usually 0
	UInt32 unknown3;		// 0x10	usually 0
	UInt32 unknown4;		// 0x14	usually 0
	UInt32 unknown5;		// 0x18	usually 0
	UInt32 cmdPointer;		// 0x1C
} WoWBinding;

- (void)getKeyBindings{
	
	// remove all previous bindings since we're grabbing new ones!
	[_bindings removeAllObjects];
	[_keyCodesWithCommands removeAllObjects];
	
	MemoryAccess *memory = [controller wowMemoryAccess];
	UInt32 offset = [offsetController offset:@"Lua_GetBindingKey"];
	UInt32 bindingsManager = 0, structPointer = 0, firstStruct = 0;
	WoWBinding bindingStruct;
	
	// find the address of our key bindings manager
	if ( [memory loadDataForObject: self atAddress: offset Buffer: (Byte*)&bindingsManager BufLength: sizeof(bindingsManager)] && bindingsManager ){
		
		// load the first struct
		[memory loadDataForObject: self atAddress: bindingsManager + 0xB4 Buffer: (Byte*)&firstStruct BufLength: sizeof(firstStruct)];
		
		structPointer = firstStruct;

		// loop through all structs!
		while ( [memory loadDataForObject: self atAddress: structPointer Buffer: (Byte*)&bindingStruct BufLength: sizeof(bindingStruct)] && bindingStruct.nextBinding > 0x0 && !(bindingStruct.nextBinding & 0x1) ){

			//PGLog(@"[Bindings] Struct found at 0x%X", structPointer);

			// initiate our variables
			NSString *key = nil;
			NSString *cmd = nil;
			char tmpKey[64], tmpCmd[64];
			tmpKey[63] = 0;
			tmpCmd[63] = 0;

			
			if ( [memory loadDataForObject: self atAddress: bindingStruct.keyPointer Buffer: (Byte *)&tmpKey BufLength: sizeof(tmpKey)-1] ){
				key = [NSString stringWithUTF8String: tmpKey];  // will stop after it's first encounter with '\0'
				//PGLog(@"[Bindings] Key %@ found at 0x%X", key, bindingStruct.keyPointer);
			}
			
			if ( [memory loadDataForObject: self atAddress: bindingStruct.cmdPointer Buffer: (Byte *)&tmpCmd BufLength: sizeof(tmpCmd)-1] ){
				cmd = [NSString stringWithUTF8String: tmpCmd];  // will stop after it's first encounter with '\0'
				//PGLog(@"[Bindings] Command %@ found at 0x%X", cmd, bindingStruct.cmdPointer);
			}
			
			// add it
			if ( [key length] && [cmd length] ){
				//PGLog(@"%@ -> %@", key, cmd);
				[_bindings setObject:cmd forKey:key];
			}
			
			//PGLog(@"[Bindings] Code %d for %@", [chatController keyCodeForCharacter:key], key);
			
			// we already made it through the list! break!
			if ( firstStruct == bindingStruct.nextBinding ){
				break;
			}
			
			// load the next one
			structPointer = bindingStruct.nextBinding;
		}
	}
	
	// now convert!
	[self convertToAscii];
	
	// find codes for our action bars
	[self mapBindingsToKeys];
}


// will convert a single, or a wow-oriented to a code
- (int)toAsciiCode:(NSString*)str{
	
	if ( !str || [str length] == 0 )
		return -1;
	
	// just to be sure
	str = [str lowercaseString];
	
	// single character
	if ( [str length] == 1 ){
		return [chatController keyCodeForCharacter:str];
	}
	
	// string
	else{
		NSNumber *code = [_commandToAscii objectForKey:str];
		
		if ( code ){
			return [code intValue];
		}
	}
	
	return -1;
}

// this function will make me want to kill myself, methinks, is it worth it?  /cry
// converts all of our "text" crap that is in the keybindings file to the actual ascii codes
- (void)convertToAscii{
	
	NSArray *allKeys = [_bindings allKeys];
	NSMutableArray *allCodes = [NSMutableArray array];
	NSMutableArray *unknownCodes = [NSMutableArray array];
	
	for ( NSString *key in allKeys ){
		
		// remove the previous commands
		[allCodes removeAllObjects];
		
		//PGLog(@"[Bindings] Command: %@ %@", [_bindings objectForKey:key], key);
		
		// this will tell us where the "-" is in our string!
		int i, splitIndex = -1;
		for ( i = 0; i < [key length]; i++ ){
			unichar code = [key characterAtIndex:i];
			
			if ( code == '-' ){
				splitIndex = i;
				break;
			}
		}
		
		NSString *command1 = nil;
		NSString *command2 = nil;
		NSString *command3 = nil;
		
		// only one command!
		if ( splitIndex == -1 ){
			command1 = [key lowercaseString];

			/*NSString *binding = [[_bindings objectForKey:key] lowercaseString];
			if ( [binding isEqualToString:[[NSString stringWithFormat:@"MULTIACTIONBAR1BUTTON1"] lowercaseString]] ){
				PGLog(@" %@", command1);
			}*/
		}
		// 2 commands
		else{
			command1 = [[key substringToIndex:splitIndex] lowercaseString];
			command2 = [[key substringFromIndex:splitIndex+1] lowercaseString];
				
			// make sure it's not just 1 character (i.e. '-')
			if ( [command2 length] > 1 ){
				
				// 2nd command could have another - in it :(  /cry
				splitIndex = -1;
				for ( i = 0; i < [command2 length]; i++ ){
					unichar code = [command2 characterAtIndex:i];
					
					if ( code == '-' ){
						splitIndex = i;
						break;
					}
				}
				
				// 3 keys!
				if ( splitIndex != -1 ){
					NSString *tmp = command2;
					command2 = [[tmp substringToIndex:splitIndex] lowercaseString];
					command3 = [[tmp substringFromIndex:splitIndex+1] lowercaseString];				
				}
			}
		}
		
		// command 1
		if ( command1 && [command1 length] == 1 ){
			[allCodes addObject:[NSNumber numberWithInt:[chatController keyCodeForCharacter:command1]]];
		}
		else if ( command1 && [command1 length] > 0 ){

			int code = [self toAsciiCode:command1];
			if ( code != -1 ){
				[allCodes addObject:[NSNumber numberWithInt:code]];
			}
			else{
				[unknownCodes addObject:command1];
			}
		}
		
		// command 2
		if ( command2 && [command2 length] == 1 ){
			[allCodes addObject:[NSNumber numberWithInt:[chatController keyCodeForCharacter:command2]]];
		}
		else if ( command2 && [command2 length] > 0 ){
			int code = [self toAsciiCode:command2];
			if ( code != -1 ){
				[allCodes addObject:[NSNumber numberWithInt:code]];
			}
			else{
				[unknownCodes addObject:command2];
			}
		}
		
		// command 2
		if ( command3 && [command3 length] == 1 ){
			[allCodes addObject:[NSNumber numberWithInt:[chatController keyCodeForCharacter:command3]]];
		}
		else if ( command3 && [command3 length] > 0 ){
			int code = [self toAsciiCode:command3];
			if ( code != -1 ){
				[allCodes addObject:[NSNumber numberWithInt:code]];
			}
			else{
				[unknownCodes addObject:command3];
			}
		}
		
		// save the codes
		NSString *binding = [[_bindings objectForKey:key] lowercaseString];
		[_keyCodesWithCommands setObject:[allCodes copy] forKey:binding];	
	}
	
	// some error checking pour moi
	if ( [unknownCodes count] ){
		for ( NSString *cmd in unknownCodes ){
			if ( ![_commandToAscii objectForKey:cmd] ){
				PGLog(@"[Bindings] Unable to find code for %@, report it to Tanaris4!", cmd);
			}
			//PGLog(@" \@\"%@\",", cmd);
		}
	}
}

- (NSArray*)bindingForCommand:(NSString*)binding{
	
	NSString *lowerCase = [binding lowercaseString];
	NSArray *codes = [_keyCodesWithCommands objectForKey:lowerCase];

	if ( codes ){
		return codes;
	}
	
	return nil;
}

// grab the key code only
- (int)codeForBinding:(NSString*)binding{
	
	NSArray *codes = [self bindingForCommand:binding];
	
	// find our code
	for ( NSNumber *tehCode in codes ){
		
		int codeVal = [tehCode intValue];
		
		if ( codeVal != kVK_Control && codeVal != kVK_Shift && codeVal != kVK_Option ){
			return codeVal;
		}
	}
	
	return -1;
}

// grab modifiers
- (int)modifierForBinding:(NSString*)binding{
	
	NSArray *codes = [self bindingForCommand:binding];
	
	int modifier = 0;
	
	// find our code + any modifiers
	for ( NSNumber *tehCode in codes ){
		
		int codeVal = [tehCode intValue];
		
		if ( codeVal == kVK_Control ){
			modifier += NSControlKeyMask;
		}
		else if ( codeVal == kVK_Shift ){
			modifier += NSShiftKeyMask;
		}
		else if ( codeVal == kVK_Option ){
			modifier += NSAlternateKeyMask;
		}
	}
	
	return modifier;
}

- (BOOL)bindingForKeyExists:(NSString*)key{

	NSDictionary *dict = [_bindingsToCodes objectForKey:key];
	
	if ( dict && [[dict objectForKey:@"Code"] intValue] >= 0 ){
		return YES;
	}
	
	return NO;
}

// this will do an "intelligent" scan to find our key bindings! Then store them for use! (reset when player is invalid)
- (void)mapBindingsToKeys{
	
	int offset = -1;
	int code = -1;
	int modifier = 0x0;
	
	//
	//	PRIMARY HOTKEY - Lower Left Action Bar or Action Bar 1
	//
	
	// scan for lower left action bar first (would be nice if we have this!
	if ( [self codeForBinding:@"MULTIACTIONBAR1BUTTON1"] >= 0 ){
		code = [self codeForBinding:@"MULTIACTIONBAR1BUTTON1"];
		modifier = [self modifierForBinding:@"MULTIACTIONBAR1BUTTON1"];
		offset = BAR6_OFFSET;
		
		PGLog(@"[Bindings] Found binding for lower left action bar: %d 0x%X 0x%X", code, modifier, offset);
	}
	// try normal bar (I could try more after this, but if they don't have either bound, they shouldn't be using this bot)
	else if ( [self codeForBinding:@"ACTIONBUTTON1"] >= 0 ){
		code = [self codeForBinding:@"ACTIONBUTTON1"];
		modifier = [self modifierForBinding:@"ACTIONBUTTON1"];
		offset = BAR1_OFFSET;
		
		PGLog(@"[Bindings] Found binding for action bar 1: %d 0x%X 0x%X", code, modifier, offset);
	}
			 
	if ( code != -1 ){
		
		[_bindingsToCodes setObject:[NSDictionary dictionaryWithObjectsAndKeys:
									 [NSNumber numberWithInt:offset],		@"Offset",
									 [NSNumber numberWithInt:code],			@"Code",
									 [NSNumber numberWithInt:modifier],		@"Modifier",
									 nil]
							 forKey:BindingPrimaryHotkey];
	}
	else{
		PGLog(@"[Bindings] No Primary Hotkey found! Bind a key to lower left action bar 1 or bar 1");
	}	
	
	//
	//	PET ATTACK HOTKEY
	//
	
	// reset
	offset = -1; code = -1; modifier = 0x0;
	
	// get pet attack!
	if ( [self codeForBinding:@"PETATTACK"] >= 0 ){
		code = [self codeForBinding:@"PETATTACK"];
		modifier = [self modifierForBinding:@"PETATTACK"];
		offset = BAR6_OFFSET;
		
		PGLog(@"[Bindings] Found binding for pet attack: %d 0x%X 0x%X", code, modifier, offset);
	}
	
	if ( code != -1 ){
		
		[_bindingsToCodes setObject:[NSDictionary dictionaryWithObjectsAndKeys:
									 [NSNumber numberWithInt:offset],		@"Offset",
									 [NSNumber numberWithInt:code],			@"Code",
									 [NSNumber numberWithInt:modifier],		@"Modifier",
									 nil]
							 forKey:BindingPetAttack];
	}
	else{
		PGLog(@"[Bindings] No Pet Attack key found! Bind a key to pet attack!");
	}
	
	//
	//	INTERACT WITH MOUSEOVER
	//
	
	// reset
	offset = -1; code = -1; modifier = 0x0;
	
	// get pet attack!
	if ( [self codeForBinding:@"INTERACTMOUSEOVER"] >= 0 ){
		code = [self codeForBinding:@"INTERACTMOUSEOVER"];
		modifier = [self modifierForBinding:@"INTERACTMOUSEOVER"];
		offset = BAR6_OFFSET;
		
		PGLog(@"[Bindings] Found binding for interact with mouseover: %d 0x%X 0x%X", code, modifier, offset);
	}
	
	if ( code != -1 ){
		
		[_bindingsToCodes setObject:[NSDictionary dictionaryWithObjectsAndKeys:
									 [NSNumber numberWithInt:offset],		@"Offset",
									 [NSNumber numberWithInt:code],			@"Code",
									 [NSNumber numberWithInt:modifier],		@"Modifier",
									 nil]
							 forKey:BindingInteractMouseover];
	}
	else{
		PGLog(@"[Bindings] No Interact with Mouseover key found! Bind a key to 'Interact with Mouseover'!");
	}
}

- (BOOL)executeBindingForKey:(NSString*)key{
	
	PGLog(@"[Bindings] Executing %@", key);
	
	NSDictionary *dict = [_bindingsToCodes objectForKey:key];
	
	if ( dict ){
		//int offset		= [[dict objectForKey:@"Offset"] intValue];
		int code		= [[dict objectForKey:@"Code"] intValue];
		int modifier	= [[dict objectForKey:@"Modifier"] intValue];
		
		// close chat box?
		if ( [controller isWoWChatBoxOpen] && code != kVK_F13 ){
			[chatController pressHotkey:kVK_Escape withModifier:0x0];
			usleep(10000);
		}
		
		[chatController pressHotkey:code withModifier:modifier];
		
		return YES;
	}
	else{
		PGLog(@"[Bindings] Unable to find binding for %@", key);
	}
	
	return NO;
}

- (int)barOffsetForKey:(NSString*)key{
	NSDictionary *dict = [_bindingsToCodes objectForKey:key];
	
	if ( dict ){
		return [[dict objectForKey:@"Offset"] intValue];
	}
	
	return -1;	
}

@end
