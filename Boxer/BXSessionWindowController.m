/* 
 Boxer is copyright 2009 Alun Bestor and contributors.
 Boxer is released under the GNU General Public License 2.0. A full copy of this license can be
 found in this XCode project at Resources/English.lproj/GNU General Public License.txt, or read
 online at [http://www.gnu.org/licenses/gpl-2.0.txt].
 */


#import "BXSessionWindowController.h"
#import "BXSessionWindowController+BXRenderController.h"
#import "BXSessionWindow.h"
#import "BXProgramPanelController.h"

#import "BXEmulator+BXRendering.h"
#import "BXCloseAlert.h"
#import "BXSession+BXDragDrop.h"


@implementation BXSessionWindowController
@synthesize programPanelController;

//Overridden to make the types explicit, so we don't have to keep casting the return values to avoid compilation warnings
- (BXSession *)document			{ return (BXSession *)[super document]; }
- (BXSessionWindow *)window		{ return (BXSessionWindow *)[super window]; }

- (BXEmulator *)emulator		{ return [[self document] emulator]; }
- (BXRenderView *)renderView	{ return [[self window] renderView]; }


//Initialisation and cleanup functions
//------------------------------------

- (void) dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver: self];
	[self setProgramPanelController: nil], [programPanelController release];
	
	[super dealloc];
}

- (void) awakeFromNib
{
	NSNotificationCenter *center	= [NSNotificationCenter defaultCenter];
	BXSessionWindow *theWindow		= [self window];
	BXRenderView *renderView		= [theWindow renderView];
	
	
	//Create our new program panel controller and attach it to our window's program panel
	BXProgramPanelController *panelController = [[[BXProgramPanelController alloc] initWithNibName: @"ProgramPanel" bundle: nil] autorelease];
	[self setProgramPanelController: panelController];
	[panelController setView: [theWindow programPanel]];
	
	
	//These are handled by BoxerRenderController, our category for rendering-related delegate tasks
	[center addObserver:	self
			selector:		@selector(windowWillLiveResize:)
			name:			@"BXRenderViewWillLiveResizeNotification"
			object:			renderView];
	[center addObserver:	self
			selector:		@selector(windowDidLiveResize:)
			name:			@"BXRenderViewDidLiveResizeNotification"
			object:			renderView];
	[center addObserver:	self
			selector:		@selector(menuDidOpen:)
			name:			NSMenuDidBeginTrackingNotification
			object:			nil];
	[center addObserver:	self
			selector:		@selector(menuDidClose:)
			name:			NSMenuDidEndTrackingNotification
			object:			nil];
	
	//While we're here, register for drag-drop file operations (used for mounting folders and such)
	[theWindow registerForDraggedTypes: [NSArray arrayWithObjects: NSFilenamesPboardType, NSStringPboardType, nil]];
	
	
	//Set up the window UI components appropriately
	
	//Show/hide the statusbar based on user's preference
	[self setStatusBarShown: [[NSUserDefaults standardUserDefaults] boolForKey: @"statusBarShown"]];
	
	//Hide the program panel by default - our parent session decides when it's appropriate to display this
	[self setProgramPanelShown: NO];
}

- (void) setDocument: (BXSession *)theSession
{
	[[self document] removeObserver: self forKeyPath: @"processDisplayName"];
	[[self programPanelController] setRepresentedObject: nil];
	
	[super setDocument: theSession];
	
	if (theSession)
	{
		id theWindow = [self window];

		//Now that we can retrieve the game's identifier from the session, use the autosaved window size for that game
		if ([theSession isGamePackage])
		{
			if ([theWindow setFrameAutosaveName: [theSession uniqueIdentifier]]) [theWindow center];
			//I hate to have to force the window to be centered but it compensates for Cocoa screwing up the position when it resizes a window from its saved frame: Cocoa pegs the window to the bottom-left origin when resizing this way, rather than the top-left as it should.
			//This comes up with non-16:10 games, since they get resized to match the 16:10 DOS ratio when they load. They would otherwise make the window travel down the screen each time they start up.
		}
		else
		{
			[theWindow setFrameAutosaveName: @"DOSWindow"];
		}
		
		//While we're here, also observe the process name of the session so that we can change the window title appropriately
		[theSession addObserver: self forKeyPath: @"processDisplayName" options: 0 context: nil];
		
		//...and add it to our panel controller, so that it can keep up with the times too
		[[self programPanelController] setRepresentedObject: theSession];
	}
}

//Sync our window title when we notice that the document's name has changed
- (void)observeValueForKeyPath: (NSString *)keyPath
					  ofObject: (id)object
						change: (NSDictionary *)change
					   context: (void *)context
{
	if ([keyPath isEqualToString: @"processDisplayName"]) [self synchronizeWindowTitleWithDocumentName];
}


//Toggling window UI components
//-----------------------------


- (BOOL) statusBarShown		{ return ![[(BXSessionWindow *)[self window] statusBar] isHidden]; }
- (BOOL) programPanelShown	{ return ![[(BXSessionWindow *)[self window] programPanel] isHidden]; }

- (void) setStatusBarShown: (BOOL)show
{
	if (show != [self statusBarShown])
	{
		BXSessionWindow *theWindow	= (BXSessionWindow *)[self window];
		BXRenderView *renderView	= [theWindow renderView];
		NSView *programPanel		= [theWindow programPanel];
		
		//temporarily override the other views' resizing behaviour so that they don't slide up as we do this
		NSUInteger oldRenderMask		= [renderView autoresizingMask];
		NSUInteger oldProgramPanelMask	= [programPanel autoresizingMask];
		[renderView		setAutoresizingMask: NSViewMinYMargin];
		[programPanel	setAutoresizingMask: NSViewMinYMargin];
		
		//toggle the resize indicator on/off also (it doesn't play nice with the program panel)
		if (!show)	[theWindow setShowsResizeIndicator: NO];
		[theWindow slideView: [theWindow statusBar] shown: show];
		if (show)	[theWindow setShowsResizeIndicator: YES];
		
		[renderView		setAutoresizingMask: oldRenderMask];
		[programPanel	setAutoresizingMask: oldProgramPanelMask];
		
		//record the current statusbar state in the user defaults
		[[NSUserDefaults standardUserDefaults] setBool: show forKey: @"statusBarShown"];
	}
}

- (void) setProgramPanelShown: (BOOL)show
{
	if (show != [self programPanelShown])
	{
		BXSessionWindow *theWindow	= (BXSessionWindow *)[self window];
		BXRenderView *renderView 	= [theWindow renderView];
		NSView *programPanel		= [theWindow programPanel];
		
		//temporarily override the other views' resizing behaviour so that they don't slide up as we do this
		NSUInteger oldRenderMask = [renderView autoresizingMask];
		[renderView setAutoresizingMask: NSViewMinYMargin];
		
		[theWindow slideView: programPanel shown: show];
		
		[renderView setAutoresizingMask: oldRenderMask];
	}
}


//Responding to interface actions
//-------------------------------

- (IBAction) toggleStatusBarShown:		(id)sender	{ [self setStatusBarShown:		![self statusBarShown]]; }
- (IBAction) toggleProgramPanelShown:	(id)sender	{ [self setProgramPanelShown:	![self programPanelShown]]; }

- (IBAction) exitFullScreen: (id)sender
{
	[self setFullScreenWithZoom: NO];
}

- (IBAction) toggleFullScreen: (id)sender
{
	//Make sure we're the key window first before any shenanigans
	[[self window] makeKeyAndOrderFront: self];
	
	BXEmulator *emulator	= [self emulator];
	BOOL isFullScreen		= [emulator isFullScreen];
	[emulator setFullScreen: !isFullScreen];
}

- (IBAction) toggleFullScreenWithZoom: (id)sender
{
	BXEmulator *emulator	= [self emulator];
	BOOL isFullScreen		= [emulator isFullScreen];
	[self setFullScreenWithZoom: !isFullScreen];
}

- (IBAction) toggleFilterType: (NSMenuItem *)sender
{
	BXEmulator *emulator	= [self emulator];
	BXFilterType filterType	= [sender tag];
	[emulator setFilterType: filterType];
	
	//If the new filter choice isn't active, then try to resize the window to an appropriate size for it
	//Todo: clarify these functions to indicate *why* the filter is inactive
	if (![emulator isFullScreen] && ![emulator filterIsActive])
	{
		NSSize newRenderSize = [emulator _minSurfaceSizeForFilterType: filterType];
		[self resizeToAccommodateViewSize: newRenderSize];
	}
}


- (BOOL) validateUserInterfaceItem: (id)theItem
{
	BXEmulator *emulator = [self emulator];
	
	//All our actions depend on the emulator being active
	if (![emulator isExecuting]) return NO;
	
	SEL theAction = [theItem action];
	BOOL hideItem; 
	
	if (theAction == @selector(toggleFilterType:))
	{
		NSInteger itemState;
		BXFilterType filterType	= [theItem tag];
		
		//Update the option state to reflect the current filter selection
		//If the filter is selected but not active at the current window size, we indicate this with a mixed state
		if		(filterType != [emulator filterType])	itemState = NSOffState;
		else if	([emulator filterIsActive])				itemState = NSOnState;
		else											itemState = NSMixedState;
		
		[theItem setState: itemState];
	}
	else if (theAction == @selector(toggleProgramPanelShown:))
	{
		if ([theItem isKindOfClass: [NSMenuItem class]])
		{
			hideItem = [self programPanelShown];
			if ([theItem tag] == 1) hideItem = !hideItem;
			[theItem setHidden: hideItem];
		}
		return [[self document] isGamePackage];
	}
	else if (theAction == @selector(toggleStatusBarShown:))
	{
		if ([theItem isKindOfClass: [NSMenuItem class]])
		{
			hideItem = [self statusBarShown];
			if ([theItem tag] == 1) hideItem = !hideItem;
			[theItem setHidden: hideItem];
		}
		return YES;
	}	
	
	//Hide and disable the exit-fullscreen option when in windowed mode
	if (theAction == @selector(exitFullScreen:))
	{
		BOOL isFullScreen = [[self emulator] isFullScreen];
		[theItem setHidden: !isFullScreen];
		return isFullScreen;
	}
	
    return YES;
}


//Handling drag-drop
//------------------

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
	NSPasteboard *pboard = [sender draggingPasteboard];	
	if ([[pboard types] containsObject: NSFilenamesPboardType])
	{
		NSArray *filePaths = [pboard propertyListForType: NSFilenamesPboardType];
		return [[self document] responseToDroppedFiles: filePaths];
	}
	else return NSDragOperationNone;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
	NSPasteboard *pboard = [sender draggingPasteboard];
    NSDragOperation sourceDragMask = [sender draggingSourceOperationMask];
 
    if ([[pboard types] containsObject: NSFilenamesPboardType])
	{
        NSArray *filePaths = [pboard propertyListForType: NSFilenamesPboardType];
		
		return [[self document] handleDroppedFiles: filePaths withLaunching: YES];
	}
	/*
	else if ([[pboard types] containsObject: NSStringPboardType])
	{
		NSString *droppedString = [pboard stringForType: NSStringPboardType];
		return [[self document] handlePastedString: droppedString];
    }
	*/
    return NO;
}


//Handling window title
//---------------------

//I give up, why is this even here? Why isn't BXSession deciding which to use?
- (void) synchronizeWindowTitleWithDocumentName
{	
	BXSession *theSession = [self document];
	if (theSession)
	{
		//For game packages, we use the standard NSDocument window title
		if ([theSession isGamePackage]) [super synchronizeWindowTitleWithDocumentName];
		
		//For regular DOS sessions, we use the current process name instead
		else [[self window] setTitle: [theSession processDisplayName]];
	}
}


//Handling dialog sheets
//----------------------

- (BOOL) windowShouldClose: (id)theWindow
{
	if (![[NSUserDefaults standardUserDefaults] boolForKey: @"suppressCloseAlert"]
		&& [[[self document] emulator] isRunningProcess])
	{
		BXCloseAlert *closeAlert = [BXCloseAlert closeAlertWhileSessionIsActive: [self document]];
		[closeAlert beginSheetModalForWindow: [self window]];
		return NO;
	}
	else return YES;
}
@end