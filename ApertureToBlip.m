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

//---------------------------------------------------------
// initWithAPIManager:
//
// This method is called when a plug-in is first loaded, and
// is a good point to conduct any checks for anti-piracy or
// system compatibility. This is also your only chance to
// obtain a reference to Aperture's export manager. If you
// do not obtain a valid reference, you should return nil.
// Returning nil means that a plug-in chooses not to be accessible.
//---------------------------------------------------------

- (id)initWithAPIManager:(id<PROAPIAccessing>)apiManager
{
	if (self = [super init]) {
		
		NSLog(@"initialising plugin");
		
		_apiManager	= apiManager;
		_exportManager = [[_apiManager apiForProtocol:@protocol(ApertureExportManager)] retain];
        
		if (!_exportManager) {
			return nil;
        }
		
		_progressLock = [[NSLock alloc] init];
		
		// Finish your initialization here
		uploading = NO;
		visitJournalAfterExport = YES;
		uploadCount = 0;
        uploadedEntryId = 0;
		
	}
	
	return self;
}

- (void)dealloc
{
	// Release the top-level objects from the nib.
	[_topLevelNibObjects makeObjectsPerformSelector:@selector(release)];
	//[_topLevelNibObjects release];
	
	[_progressLock release];
	[_exportManager release];
	
	[super dealloc];
}


#pragma mark -
// UI Methods
#pragma mark UI Methods

- (NSView *)settingsView
{
	if (nil == settingsView) {
        
		// Load the nib using NSNib, and retain the array of top-level objects so we can release
		// them properly in dealloc
		NSBundle *myBundle = [NSBundle bundleForClass:[self class]];
		NSNib *myNib = [[NSNib alloc] initWithNibNamed:@"ApertureToBlip" bundle:myBundle];
		if ([myNib instantiateWithOwner:self topLevelObjects:&_topLevelNibObjects])
		{
			[_topLevelNibObjects retain];
		}
		[myNib release];
	}
	
	return settingsView;
}

- (NSView *)firstView
{
	return firstView;
}

- (NSView *)lastView
{
	return lastView;
}

- (void)willBeActivated {
	
	self.dataController = [[DataController alloc] init];
	api = [[API alloc] initWithKey:@"" secret:@""];
	if (![self.dataController.auth_username isEqualToString: @"-1"]){
		api.authToken = self.dataController.auth_token;
		connectLabel.stringValue = [NSString stringWithFormat:@"Linked to %@'s journal", self.dataController.auth_username];
		connectButton.title = @"Unlink";
    }
    
    if (self.dataController.visitJournalAfterExport){
        visitJournal.state = YES;
    }
    else {
        visitJournal.state = NO;
    }
	
	// fetch the server timestamp
	[api listen:@"ResponseParsed" for:self selector:@selector(timeReceived:)];
	[api request:@"get" resource:@"time" params:nil postdata:nil withImage:nil withAuth:0];
	
	entryTitle.delegate = self;
	entryDesc.delegate = self;
	entryTags.delegate = self;
	
	self.entries = [[NSMutableArray alloc] initWithCapacity:0];
	
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
	NSString *shouldBeUploaded;
	
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
	for (i = 0; i < l; i++){
		
		properties = [_exportManager propertiesWithoutThumbnailForImageAtIndex:i];
		
		exif = [properties objectForKey:@"kExportKeyEXIFProperties"];
		exifKeys = [exif allKeys];
		if ([exifKeys containsObject:@"CaptureDayOfMonth"]){
			tmpDate = [NSString stringWithFormat:@"%@ %@ %@ %@", [days objectAtIndex:[[exif objectForKey:@"CaptureDayOfWeek"] intValue]], [exif objectForKey:@"CaptureDayOfMonth"], [months objectAtIndex:[[exif objectForKey:@"CaptureMonthOfYear"] intValue]-1], [exif objectForKey:@"CaptureYear"]];
			uploadCount++;
			shouldBeUploaded = @"1";
        }
		else {
			tmpDate = @"(No date found, won't be uploaded)";
			shouldBeUploaded = @"0";
        }
		
		iptc = [properties objectForKey:@"kExportKeyIPTCProperties"];
		iptcKeys = [iptc allKeys];
		
		if ([iptcKeys containsObject:@"ObjectName"]){
			tmpTitle = [iptc objectForKey:@"ObjectName"];
        }
		else {
			tmpTitle = @"";
        }
		
		if ([iptcKeys containsObject:@"Caption/Abstract"]){
			tmpDesc = [iptc objectForKey:@"Caption/Abstract"];
        }
		else {
			tmpDesc= @"";
        }
		
		if ([iptcKeys containsObject:@"Keywords"]){
			tmpTags = [iptc objectForKey:@"Keywords"];
        }
		else {
			tmpTags = @"";
        }
        
		[self.entries addObject: [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                  tmpTitle, @"title",
                                  tmpDesc, @"desc",
                                  tmpTags, @"tags",
                                  tmpDate, @"date",
                                  shouldBeUploaded, @"shouldBeUploaded",
                                  nil]];
		filename = [[properties objectForKey:kExportKeyReferencedMasterPath] componentsSeparatedByString:@"/"];
		[entrySelector addItemWithTitle:[filename objectAtIndex:[filename count] - 1]];
	}
	
	[self updateEntryOptions:0];
}

// get/time was received
- (void) timeReceived:(NSNotification *) notif {
	
	TBXML *xmlDoc = [notif object];
	TBXMLElement *data = [TBXML childElementNamed:@"data" parentElement:xmlDoc.rootXMLElement];
	int timestamp = [[TBXML textForElement:[TBXML childElementNamed:@"timestamp" parentElement:data]] intValue];
	
	api.timestampOffset = timestamp-(int)[[NSDate date] timeIntervalSince1970];
	
	[api unlisten:@"ResponseParsed" for:self];
}

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

/* sign in methods */

- (IBAction) connectButtonPressed:(id)sender {
	if ([connectButton.title isEqualToString:@"Verify"]){
		[api listen:@"ResponseParsed" for:self selector:@selector(tokenReceived:)];
		[api request:@"get" resource:@"token" params:[NSDictionary dictionaryWithObjectsAndKeys:tempToken.stringValue, @"temp_token", nil] postdata:nil withImage:nil withAuth:1];
    }
	else if ([connectButton.title isEqualToString:@"Unlink"]){
        
		NSAlert *alert = [[[NSAlert alloc] init] autorelease];
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
        
		self.dataController.auth_token=@"-1";
		self.dataController.auth_username=@"-1";
		[self.dataController saveData];
        
		connectButton.title=@"Link";
		connectLabel.stringValue=@"Start by linking to your Blipfoto journal:";
    }
}


- (void) tokenReceived:(NSNotification *)notif {
	
	[api unlisten:@"ResponseParsed" for:self];
	
	TBXML *xmlDoc = [notif object];
	int errorCode = [api responseError:xmlDoc];
	
	tempToken.stringValue = @"";
	
	if (errorCode > 0){
		
		NSAlert *alert = [[[NSAlert alloc] init] autorelease];
		[alert addButtonWithTitle:@"OK"];
		[alert setMessageText:@"Couldn't link journal"];
		[alert setInformativeText:[NSString stringWithFormat:@"It looks like you copied the code incorrectly or didn't give permission to the app (error %d).", errorCode]];
		[alert setAlertStyle:NSInformationalAlertStyle];
		[alert beginSheetModalForWindow:[[self settingsView] window] modalDelegate:self didEndSelector:nil contextInfo:nil];
		
    }
	else {
		TBXMLElement *data = [TBXML childElementNamed:@"data" parentElement:xmlDoc.rootXMLElement];
		NSString *displayName = [TBXML textForElement:[TBXML childElementNamed:@"display_name" parentElement:data]];
		NSString *authToken = [TBXML textForElement:[TBXML childElementNamed:@"token" parentElement:data]];
		
		// save prefs
		self.dataController.auth_token = authToken;
		self.dataController.auth_username = displayName;
		[self.dataController saveData];
		
		api.authToken = authToken;
		
		[tempToken setHidden:YES];
		connectLabel.stringValue = [NSString stringWithFormat:@"Linked to %@'s journal", displayName];
		connectButton.title = @"Unlink";
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

- (BOOL)control:(NSControl*)control textView:(NSTextView*)textView doCommandBySelector:(SEL)commandSelector {
	
    BOOL result = NO;
	
    if (control == entryDesc && commandSelector == @selector(insertNewline:)) {
        [textView insertNewlineIgnoringFieldEditor:self];
        result = YES;
    }
	
    return result;
}


- (void)willBeDeactivated
{
	NSLog(@"deactivated");
	[self.dataController release];
	[self.entries release];
}

#pragma mark
// Aperture UI Controls
#pragma mark Aperture UI Controls

- (BOOL)allowsOnlyPlugInPresets
{
	return NO;
}

- (BOOL)allowsMasterExport
{
	return YES;
}

- (BOOL)allowsVersionExport
{
	return YES;
}

- (BOOL)wantsFileNamingControls
{
	return NO;
}

- (void)exportManagerExportTypeDidChange
{
	
}


#pragma mark -
// Save Path Methods
#pragma mark Save/Path Methods

- (BOOL)wantsDestinationPathPrompt
{
	return NO;
}

- (NSString *)destinationPath
{
	return [@"~/Documents" stringByExpandingTildeInPath];
}

- (NSString *)defaultDirectory
{
	return [@"~/Documents" stringByExpandingTildeInPath];
}


#pragma mark -
// Export Process Methods
#pragma mark Export Process Methods

- (void)exportManagerShouldBeginExport {
	if ([self.dataController.auth_username isEqualToString:@"-1"]){
		NSAlert *alert = [[[NSAlert alloc] init] autorelease];
		[alert addButtonWithTitle:@"OK"];
		[alert setMessageText:@"Not linked to journal"];
		[alert setInformativeText:@"You must link Aperture to your Blipfoto journal before you can export images."];
		[alert setAlertStyle:NSInformationalAlertStyle];
		[alert beginSheetModalForWindow:[[self settingsView] window] modalDelegate:self didEndSelector:nil contextInfo:nil];
		
    }
	else {
        
        self.dataController.visitJournalAfterExport = visitJournal.state;
        [self.dataController saveData];
		
		[self lockProgress];
		exportProgress.totalValue = 100;
		exportProgress.currentValue = 0;
		exportProgress.indeterminateProgress = NO;
		exportProgress.message = [@"Starting upload..." retain];
		[self unlockProgress];
		
		uploadLog = [[NSMutableArray alloc] initWithCapacity:0];
		
		visitJournalAfterExport = visitJournal.state;
		
		[_exportManager shouldBeginExport];
	}
}



- (void)exportManagerWillBeginExportToPath:(NSString *)path {
    
}

- (BOOL)exportManagerShouldExportImageAtIndex:(unsigned)index {
	return [[[entries objectAtIndex:index] objectForKey:@"shouldBeUploaded"] intValue] > 0;
}

- (void)exportManagerWillExportImageAtIndex:(unsigned)index {
	
}

- (BOOL)exportManagerShouldWriteImageData:(NSData *)imageData toRelativePath:(NSString *)path forImageAtIndex:(unsigned)index {
	
	[self lockProgress];
	exportProgress.totalValue = 100;
	exportProgress.currentValue = 0;
	exportProgress.message = [NSString stringWithFormat:@"Uploading %d of %d", index + 1, uploadCount];
	[self unlockProgress];
    
	NSDictionary *entryData = [entries objectAtIndex:index];
	NSMutableDictionary *params = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                   [entryData objectForKey:@"title"],
                                   @"entry_title",
                                   [entryData objectForKey:@"desc"],
                                   @"entry_description",
                                   [entryData objectForKey:@"tags"],
                                   @"entry_tags",
                                   nil];
    
	[api listen:@"ResponseParsed" for:self selector:@selector(uploadComplete:)];
	[api listen:@"ProgressUpdated" for:self selector:@selector(uploadProgressUpdated:)];
	uploading = YES;
	[api request:@"post" resource:@"entry" params:nil postdata:params withImage:imageData withAuth:2];
	while(uploading) {
		[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
    }
	
	NSLog(@"post request done");
	
	return NO;
}

- (void) uploadComplete:(NSNotification *) notify {
	NSLog(@"ok, upload complete");
	NSString *message;
	TBXML *xmlDoc = [notify object];
	int errorCode = [api responseError:xmlDoc];
	if (errorCode > 0){
		TBXMLElement *error = [TBXML childElementNamed:@"error" parentElement:xmlDoc.rootXMLElement];
		message = [NSString stringWithFormat:@"Image %d not published - %@", (int)[uploadLog count]+ 1, [TBXML textForElement:[TBXML childElementNamed:@"message" parentElement:error]]];
    }
	else {
        
        
        uploadedEntryId = [[TBXML textForElement: [TBXML childElementNamed:@"entry_id" parentElement:[TBXML childElementNamed:@"data" parentElement:xmlDoc.rootXMLElement]]] intValue];
        
        
		message = [NSString stringWithFormat:@"Image %d published succesfully", (int)[uploadLog count] + 1];
    }
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

- (void)exportManagerDidWriteImageDataToRelativePath:(NSString *)relativePath forImageAtIndex:(unsigned)index {
	
}

- (void)exportManagerDidFinishExport {
	
	[api unlisten:@"ResponseParsed" for:self];
	[api unlisten:@"ProgressUpdated" for:self];
	
	NSLog(@"%@", [uploadLog componentsJoinedByString:@"\n"]);
	[_exportManager shouldFinishExport];
	
	if (visitJournalAfterExport){
		[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://www.blipfoto.com/entry/%d", uploadedEntryId]]];
    }
}

- (void)exportManagerShouldCancelExport {
	[_exportManager shouldCancelExport];
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
