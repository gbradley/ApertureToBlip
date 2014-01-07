//
//	Blipfoto.m
//	Blipfoto
//
//	Created by Graham Bradley on 06/02/2011.
//	Copyright __MyCompanyName__ 2011. All rights reserved.
//

#import "ApertureToBlip.h"
#import "DataController.h"

@implementation ApertureToBlip

@synthesize dataController, api, entries;

- (id) initWithAPIManager:(id<PROAPIAccessing>)apiManager {
	if (self = [super init]) {
		
		_apiManager	= apiManager;
		_exportManager = [_apiManager apiForProtocol:@protocol(ApertureExportManager)];
        
		if (!_exportManager) {
			return nil;
        }
		_progressLock = [[NSLock alloc] init];
        
		uploading = NO;
		uploadCount = 0;
        uploadedEntryId = 0;
	}
	
	return self;
}

#pragma mark -
// UI Methods
#pragma mark UI Methods

- (NSView *) settingsView {
	if (nil == settingsView) {
		NSBundle *myBundle = [NSBundle bundleForClass:[self class]];
		NSNib *myNib = [[NSNib alloc] initWithNibNamed:@"ApertureToBlip" bundle:myBundle];
        NSArray __autoreleasing *pointer = _topLevelNibObjects;
		[myNib instantiateWithOwner:self topLevelObjects:&pointer];
	}
	
	return settingsView;
}

- (NSView *) firstView {
	return firstView;
}

- (NSView *) lastView {
	return lastView;
}

- (void) willBeActivated {
	
	self.dataController = [[DataController alloc] init];
	api = [[API alloc] initWithKey:@"key" secret:@"secret"];

	if (![self.dataController.displayName isEqualToString:@""]) {
		api.userToken = self.dataController.userToken;
        api.userSecret = self.dataController.userSecret;
		connectLabel.stringValue = [NSString stringWithFormat:@"Linked to %@'s journal", self.dataController.displayName];
		connectButton.title = @"Unlink";
    }
    
    visitJournal.state = self.dataController.visitJournalAfterExport;
    
    // fetch the server timestamp
    [api generateTimestamp];
	
	entryTitle.delegate = self;
	entryDesc.delegate = self;
	entryTags.delegate = self;
	
	self.entries = [[NSMutableArray alloc] initWithCapacity:0];
	
    // inspect the image's EXIF and IPTC fields
	NSDictionary *properties;
	NSDictionary *exif;
	NSArray *exifKeys;
	NSDictionary *iptc;
	NSArray *iptcKeys;
	NSArray *filename;
	NSString *tmpTitle;
	NSString *tmpDesc;
	NSString *tmpTags;
	NSString *tmpDate;
	BOOL shouldBeUploaded;
	
	NSArray *days = [NSArray arrayWithObjects:@"Sunday",
					 @"Monday",
					 @"Tuesday",
					 @"Wednesday",
					 @"Thursday",
					 @"Friday",
					 @"Saturday",
					 nil];
	
	NSArray *months = [NSArray arrayWithObjects:@"January",
					   @"February",
					   @"March",
					   @"April",
					   @"May",
					   @"June",
					   @"July",
					   @"August",
					   @"September",
					   @"October",
					   @"November",
					   @"December",
					   nil];
	
	[entrySelector removeAllItems];
	int i;
	int l = [_exportManager imageCount];
	for (i = 0; i < l; i++) {
		
		properties = [_exportManager propertiesWithoutThumbnailForImageAtIndex:i];
		
		exif = [properties objectForKey:@"kExportKeyEXIFProperties"];
		exifKeys = [exif allKeys];
		if ([exifKeys containsObject:@"CaptureDayOfMonth"]) {
			tmpDate = [NSString stringWithFormat:@"%@ %@ %@ %@", [days objectAtIndex:[[exif objectForKey:@"CaptureDayOfWeek"] intValue]], [exif objectForKey:@"CaptureDayOfMonth"], [months objectAtIndex:[[exif objectForKey:@"CaptureMonthOfYear"] intValue]-1], [exif objectForKey:@"CaptureYear"]];
			uploadCount++;
			shouldBeUploaded = YES;
        } else {
			tmpDate = @"(No date found, won't be uploaded)";
			shouldBeUploaded = NO;
        }
		
		iptc = [properties objectForKey:@"kExportKeyIPTCProperties"];
		iptcKeys = [iptc allKeys];
		
		if ([iptcKeys containsObject:@"ObjectName"]) {
			tmpTitle = [iptc objectForKey:@"ObjectName"];
        } else {
			tmpTitle = @"";
        }
		
		if ([iptcKeys containsObject:@"Caption/Abstract"]) {
			tmpDesc = [iptc objectForKey:@"Caption/Abstract"];
        } else {
			tmpDesc= @"";
        }
		
		if ([iptcKeys containsObject:@"Keywords"]) {
			tmpTags = [iptc objectForKey:@"Keywords"];
        } else {
			tmpTags = @"";
        }
        
		[self.entries addObject: [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                  tmpTitle, @"title",
                                  tmpDesc, @"desc",
                                  tmpTags, @"tags",
                                  tmpDate, @"date",
                                  [NSNumber numberWithBool:shouldBeUploaded], @"shouldBeUploaded",
                                  nil]];
		filename = [[properties objectForKey:kExportKeyReferencedMasterPath] componentsSeparatedByString:@"/"];
		[entrySelector addItemWithTitle:[filename objectAtIndex:[filename count] - 1]];
	}
	
	[self updateEntryOptions:0];
}

#pragma mark
// Plugin UI Controls
#pragma mark Plugin UI Controls

- (void) updateEntryOptions:(int) index {
	
	[entryThumbnail setImage:[_exportManager thumbnailForImageAtIndex:index size:kExportThumbnailSizeTiny]];
	
	NSDictionary *entryData = [self.entries objectAtIndex:index];
	
	entryDate.stringValue = [entryData objectForKey:@"date"];
	entryTitle.stringValue = [entryData objectForKey:@"title"];
	entryDesc.stringValue = [entryData objectForKey:@"desc"];
	entryTags.stringValue = [entryData objectForKey:@"tags"];
    
}

- (IBAction) switchImage:(id)sender {
	[self updateEntryOptions:[entrySelector indexOfSelectedItem]];
}

- (IBAction) connectButtonPressed:(id)sender {
	if ([connectButton.title isEqualToString:@"Verify"]){
		
        [api request:@"get" resource:@"token" params:[NSMutableDictionary dictionaryWithObjectsAndKeys:tempToken.stringValue, @"temp_token", nil] authType:APIAuthTypeApplication onSuccess:^(NSDictionary *response) {
            
            NSDictionary *data = [response objectForKey:@"data"];
            
            // save prefs
            self.dataController.userToken = [data objectForKey:@"token"];
            self.dataController.userSecret = [data objectForKey:@"secret"];
            self.dataController.displayName = [data objectForKey:@"display_name"];
            [self.dataController saveData];
            
            api.userToken = self.dataController.userToken;
            api.userSecret = self.dataController.userSecret;
            
            [tempToken setHidden:YES];
            connectLabel.stringValue = [NSString stringWithFormat:@"Linked to %@'s journal", self.dataController.displayName];
            connectButton.title = @"Unlink";
            
        } onFailure:^(NSError *error) {
            
            NSAlert *alert = [[NSAlert alloc] init];
            [alert addButtonWithTitle:@"OK"];
            [alert setMessageText:@"Couldn't link journal"];
            [alert setInformativeText:[NSString stringWithFormat:@"It looks like you copied the code incorrectly or didn't give permission to the app (error %ld).", (long)error.code]];
            [alert setAlertStyle:NSInformationalAlertStyle];
            [alert beginSheetModalForWindow:[[self settingsView] window] modalDelegate:self didEndSelector:nil contextInfo:nil];
            
        }];

    }
	else if ([connectButton.title isEqualToString:@"Unlink"]){
        
		NSAlert *alert = [[NSAlert alloc] init];
		[alert addButtonWithTitle:@"OK"];
		[alert addButtonWithTitle:@"Cancel"];
		[alert setMessageText:@"Unlink journal"];
		[alert setInformativeText:@"Unlinking your journal will mean you won't be able to publish to Blipfoto."];
		[alert setAlertStyle:NSInformationalAlertStyle];
		[alert beginSheetModalForWindow:[sender window] modalDelegate:self didEndSelector:@selector(alertDidEnd:returnCode:contextInfo:) contextInfo:nil];
		
    }
	else {
		connectLabel.stringValue = @"Enter 6 digit code:";
		connectButton.title = @"Verify";
		[tempToken setHidden : NO];
		[[tempToken window] makeFirstResponder:tempToken];
		[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://www.blipfoto.com/getpermission/769357"]];
	}
}

- (void)alertDidEnd:(NSAlert *)alert returnCode:(int)returnCode contextInfo:(void *)contextInfo{
	if (returnCode == NSAlertFirstButtonReturn) {
        
		self.dataController.userToken = @"";
        self.dataController.userSecret = @"";
		self.dataController.displayName = @"";
		[self.dataController saveData];
        
		connectButton.title = @"Link";
		connectLabel.stringValue=@"Start by linking to your Blipfoto journal:";
    }
}

- (IBAction) formattingButtonPressed:(id)sender {
    
    int offset;
    
    NSText *textBox = [entryDesc currentEditor];
    NSString *text = textBox.string;
    NSRange range = [textBox selectedRange];
    int insertionPoint = range.location;
    
    if (sender == linkButton){
        
		[textBox setString:[NSString stringWithFormat:@"%@[url=]%@[/url]%@", [text substringToIndex:insertionPoint], [text substringWithRange:range], [text substringFromIndex:insertionPoint + range.length]]];
        range.location += 5;
        range.length = 0;
        
    } else {
        
        NSString *chr = [[((NSButton *)sender) title] lowercaseString];
        offset=3;
        
		[textBox setString:[NSString stringWithFormat:@"%@[%@]%@[/%@]%@", [text substringToIndex:insertionPoint], chr, [text substringWithRange:range], chr, [text substringFromIndex:insertionPoint + range.length]]];
        range.location += range.length ? range.length + 7 : 3;
        range.length = 0;
    }
    [textBox setSelectedRange:range];
}

- (void)controlTextDidChange:(NSNotification *) notify {
    
	if (notify.object==entryTitle){
		[[self.entries objectAtIndex:[entrySelector indexOfSelectedItem]] setObject:entryTitle.stringValue forKey:@"title"];
    }
	else if (notify.object==entryDesc){
		[[self.entries objectAtIndex:[entrySelector indexOfSelectedItem]] setObject:entryDesc.stringValue forKey:@"desc"];
    }
	else if (notify.object==entryTags){
		[[self.entries objectAtIndex:[entrySelector indexOfSelectedItem]] setObject:entryTags.stringValue forKey:@"tags"];
	}
}

/* Allow new lines in text field - http://developer.apple.com/library/mac/#qa/qa1454/_index.html */

- (BOOL) control:(NSControl*)control textView:(NSTextView*)textView doCommandBySelector:(SEL)commandSelector {
	
    BOOL result = NO;
	
    if (control == entryDesc && commandSelector == @selector(insertNewline:)) {
        [textView insertNewlineIgnoringFieldEditor:self];
        result = YES;
    }
	
    return result;
}

- (void)willBeDeactivated {

}

#pragma mark
// Aperture UI Controls
#pragma mark Aperture UI Controls

- (BOOL)allowsOnlyPlugInPresets {
	return NO;
}

- (BOOL)allowsMasterExport {
	return YES;
}

- (BOOL)allowsVersionExport {
	return YES;
}

- (BOOL) wantsFileNamingControls {
	return NO;
}

- (void) exportManagerExportTypeDidChange {
}


#pragma mark -
// Save Path Methods
#pragma mark Save/Path Methods

- (BOOL) wantsDestinationPathPrompt {
	return NO;
}

- (NSString *) destinationPath {
	return [@"~/Documents" stringByExpandingTildeInPath];
}

- (NSString *) defaultDirectory {
	return [@"~/Documents" stringByExpandingTildeInPath];
}


#pragma mark -
// Export Process Methods
#pragma mark Export Process Methods

- (void) exportManagerShouldBeginExport {
	if ([self.dataController.displayName isEqualToString:@""]) {
		NSAlert *alert = [[NSAlert alloc] init];
		[alert addButtonWithTitle:@"OK"];
		[alert setMessageText:@"Not linked to journal"];
		[alert setInformativeText:@"You must link Aperture to your Blipfoto journal before you can export images."];
		[alert setAlertStyle:NSInformationalAlertStyle];
		[alert beginSheetModalForWindow:[[self settingsView] window] modalDelegate:self didEndSelector:nil contextInfo:nil];
		
    } else {
        
        self.dataController.visitJournalAfterExport = visitJournal.state;
        [self.dataController saveData];
		
		[self lockProgress];
		exportProgress.totalValue = 100;
		exportProgress.currentValue = 0;
		exportProgress.indeterminateProgress = NO;
		exportProgress.message = @"Starting upload...";
		[self unlockProgress];
		
		uploadLog = [[NSMutableArray alloc] initWithCapacity:0];
		
		[_exportManager shouldBeginExport];
	}
}

- (void) exportManagerWillBeginExportToPath:(NSString *)path {
    
}

- (BOOL) exportManagerShouldExportImageAtIndex:(unsigned)index {
	return [[[entries objectAtIndex:index] objectForKey:@"shouldBeUploaded"] boolValue];
}

- (void) exportManagerWillExportImageAtIndex:(unsigned)index {
	
}

- (BOOL) exportManagerShouldWriteImageData:(NSData *)imageData toRelativePath:(NSString *)path forImageAtIndex:(unsigned)index {
	
	[self lockProgress];
	exportProgress.totalValue = 100;
	exportProgress.currentValue = 0;
	exportProgress.message = [NSString stringWithFormat:@"Uploading %d of %d", index + 1, uploadCount];
	[self unlockProgress];
    
	NSDictionary *entryData = [entries objectAtIndex:index];
	NSMutableDictionary *params = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                   [entryData objectForKey:@"title"], @"title",
                                   [entryData objectForKey:@"desc"], @"description",
                                   [entryData objectForKey:@"tags"], @"tags",
                                   imageData, @"image",
                                   nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(uploadProgressUpdated:) name:@"PublishProgressUpdated" object:nil];
    
    uploading = YES;
    
    [api request:@"post" resource:@"entry" params:params authType:APIAuthTypeUser onSuccess:^(NSDictionary *response) {
        
        [[NSNotificationCenter defaultCenter] removeObserver:self name:@"PublishProgressUpdated" object:nil];
        
        NSDictionary *data = [response objectForKey:@"data"];
        uploadedEntryId = [data objectForKey:@"entry_id"];
    
		[self uploadFinishedWithMessage:[NSString stringWithFormat:@"Image %d published succesfully", (int)[uploadLog count] + 1]];
        
    } onFailure:^(NSError *error) {
        
        [[NSNotificationCenter defaultCenter] removeObserver:self name:@"PublishProgressUpdated" object:nil];
        
        [self uploadFinishedWithMessage:[NSString stringWithFormat:@"Image %d not published - %@", (int)[uploadLog count]+ 1, [error.userInfo objectForKey:NSLocalizedDescriptionKey]]];
    }];
    
    while (uploading) {
		[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
    }
	
	return NO;
}

- (void) exportManagerDidWriteImageDataToRelativePath:(NSString *)relativePath forImageAtIndex:(unsigned)index {
}

- (void) exportManagerDidFinishExport {
	
	[_exportManager shouldFinishExport];
	
	if (self.dataController.visitJournalAfterExport) {
		[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://www.blipfoto.com/entry/%@", uploadedEntryId]]];
    }
}

- (void) exportManagerShouldCancelExport {
	[_exportManager shouldCancelExport];
}

#pragma mark -
// Upload Progress Methods
#pragma mark Upload Progress Methods

- (void) uploadFinishedWithMessage:(NSString *) message {
    [self lockProgress];
	exportProgress.message = message;
	[self unlockProgress];
	[uploadLog addObject:message];
	
	[NSTimer scheduledTimerWithTimeInterval:3 target:self selector:@selector(uploadNext:) userInfo:nil repeats:NO];
}

- (void) uploadNext:(NSTimer *) timer {
	uploading = NO;
}

- (void) uploadProgressUpdated:(NSNotification *) notify {
	[self lockProgress];
	exportProgress.currentValue = floor([[notify object] floatValue] * 100);
	[self unlockProgress];
}


#pragma mark -
// Progress Methods
#pragma mark Progress Methods

- (ApertureExportProgress *)progress {
	return &exportProgress;
}

- (void)lockProgress {
	if (!_progressLock)
		_progressLock = [[NSLock alloc] init];
	[_progressLock lock];
}

- (void)unlockProgress {
	[_progressLock unlock];
}

@end
