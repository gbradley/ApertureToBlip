//
//	Blipfoto.h
//	Blipfoto
//
//	Created by Graham Bradley on 06/02/2011.
//	Copyright __MyCompanyName__ 2011. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>
#import "ApertureExportManager.h"
#import "ApertureExportPlugIn.h"
#import "DataController.h"
#import "API.h"

@interface ApertureToBlip : NSObject <ApertureExportPlugIn, NSTextFieldDelegate> {
	// The cached API Manager object, as passed to the -initWithAPIManager: method.
	id _apiManager;
	
	// The cached Aperture Export Manager object - you should fetch this from the API Manager during -initWithAPIManager:
	NSObject<ApertureExportManager, PROAPIObject> *_exportManager;
	
	// The lock used to protect all access to the ApertureExportProgress structure
	NSLock *_progressLock;
	
	// Top-level objects in the nib are automatically retained - this array
	// tracks those, and releases them
	NSArray *_topLevelNibObjects;
	
	// The structure used to pass all progress information back to Aperture
	ApertureExportProgress exportProgress;
    
	// Outlets to your plug-ins user interface
	IBOutlet NSView *settingsView;
	IBOutlet NSView *firstView;
	IBOutlet NSView *lastView;
	
	IBOutlet NSPopUpButton *entrySelector;
	IBOutlet NSTextField *entryDate;
	IBOutlet NSTextField *entryTitle;
	IBOutlet NSTextField *entryDesc;
	IBOutlet NSTextField *entryTags;
	IBOutlet NSImageView *entryThumbnail;
	
	IBOutlet NSTextField *connectLabel;
	IBOutlet NSButton *connectButton;
	IBOutlet NSTextField *tempToken;
	IBOutlet NSButton *visitJournal;
    
    IBOutlet NSButton *italicButton;
    IBOutlet NSButton *underlineButton;
    IBOutlet NSButton *boldButton;
    IBOutlet NSButton *strikeButton;
    IBOutlet NSButton *linkButton;
	
	NSMutableArray *entries;
	
	DataController *dataController;
	API *api;
	BOOL uploading;
	int uploadCount;
    NSString *uploadedEntryId;
	NSMutableArray *uploadLog;
}

@property (copy, nonatomic) DataController *dataController;
@property (copy, nonatomic) API *api;
@property (retain) NSMutableArray *entries;

- (IBAction) switchImage:(id)sender;
- (IBAction) connectButtonPressed:(id)sender;
- (IBAction) formattingButtonPressed:(id)sender;
- (void) updateEntryOptions:(int) index;

@end
