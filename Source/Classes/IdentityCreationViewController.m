/* Copyright (C) 2009-2010 Mikkel Krautz <mikkel@krautz.dk>

   All rights reserved.

   Redistribution and use in source and binary forms, with or without
   modification, are permitted provided that the following conditions
   are met:

   - Redistributions of source code must retain the above copyright notice,
     this list of conditions and the following disclaimer.
   - Redistributions in binary form must reproduce the above copyright notice,
     this list of conditions and the following disclaimer in the documentation
     and/or other materials provided with the distribution.
   - Neither the name of the Mumble Developers nor the names of its
     contributors may be used to endorse or promote products derived from this
     software without specific prior written permission.

   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
   ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
   A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE FOUNDATION OR
   CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
   EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
   PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
   PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
   LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
   NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
   SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

#import "IdentityCreationViewController.h"
#import "TableViewTextFieldCell.h"
#import "IdentityCreationProgressView.h"
#import "UINavigationController-AnimationAdditions.h"
#import "IdentityViewController.h"
#import "Database.h"
#import "Identity.h"

#import <MumbleKit/MKCertificate.h>

static void ShowAlertDialog(NSString *title, NSString *msg) {
	dispatch_async(dispatch_get_main_queue(), ^{
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title message:msg delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
		[alert show];
	});
}

@implementation IdentityCreationViewController

#pragma mark -
#pragma mark Initialization

- (id) init {
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (self == nil)
		return nil;

	_identityName = @"Joe Schmoe";
	_emailAddress = @"joe@schmoe.ca";

	return self;
}

- (void) dealloc {
	[super dealloc];
}

- (void) viewWillAppear:(BOOL)animated {
	[[self navigationItem] setTitle:@"Create Identity"];

	UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancelButtonClicked:)];
	[[self navigationItem] setLeftBarButtonItem:cancelButton];
	[cancelButton release];

	UIBarButtonItem *createButton = [[UIBarButtonItem alloc] initWithTitle:@"Create" style:UIBarButtonItemStyleDone target:self action:@selector(createButtonClicked:)];
	[[self navigationItem] setRightBarButtonItem:createButton];
	[createButton release];
}

#pragma mark -
#pragma mark Table view data source

- (NSInteger) numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}


- (NSInteger) tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == 0) // Avatar
		return 0;
	if (section == 1) // Identity
		return 2;

	return 0;
}

- (NSString *) tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == 0) // Avatar
		return @"Avatar";
	if (section == 1) // Identity
		return @"Identity";

	return @"Default";
}

- (NSString *) tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == 0) // Avatar
		return @"Not Yet Implemented";

	return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if ([indexPath section] == 1) { // Identity
		NSUInteger row = [indexPath row];
		static NSString *CellIdentifier = @"IdentityCreationTextFieldCell";
		TableViewTextFieldCell *cell = (TableViewTextFieldCell *)[tableView dequeueReusableCellWithIdentifier:CellIdentifier];
		if (cell == nil) {
			cell = [[[TableViewTextFieldCell alloc] initWithReuseIdentifier:CellIdentifier] autorelease];
		}

		[cell setTarget:self];

		if (row == 0) { // Name
			[cell setLabel:@"Name"];
			[cell setPlaceholder:@"Optional"];
			[cell setAutocapitalizationType:UITextAutocapitalizationTypeWords];
			[cell setValueChangedAction:@selector(nameChanged:)];
			[cell setTextValue:_identityName];
		} else if (row == 1) { // E-mail
			[cell setLabel:@"Email"];
			[cell setPlaceholder:@"Optional"];
			[cell setAutocapitalizationType:UITextAutocapitalizationTypeNone];
			[cell setValueChangedAction:@selector(emailChanged:)];
			[cell setTextValue:_emailAddress];
		}

		return cell;
	}

	return nil;
}

#pragma mark -
#pragma mark Target/actions

- (void) cancelButtonClicked:(UIBarButtonItem *)cancelButton {
	[[self navigationController] dismissModalViewControllerAnimated:YES];
}

- (void) createButtonClicked:(UIBarButtonItem *)doneButton {
	IdentityCreationProgressView *progress = [[IdentityCreationProgressView alloc] initWithName:_identityName email:_emailAddress delegate:self];
	[[self navigationController] pushViewController:progress animated:YES];
	[progress release];

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		OSStatus err = noErr;

		// Generate a certificate for this identity.
		MKCertificate *cert = [MKCertificate selfSignedCertificateWithName:_identityName email:_emailAddress];
		NSData *pkcs12 = [cert exportPKCS12WithPassword:@""];
		if (pkcs12 == nil) {
			ShowAlertDialog(@"Unable to generate certificate",
							@"Mumble was unable to generate a certificate for the your identity.");
		} else {
			NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:@"", kSecImportExportPassphrase, nil];
			NSArray *items = nil;
			err = SecPKCS12Import((CFDataRef)pkcs12, (CFDictionaryRef)dict, (CFArrayRef *)&items);
			if (err == errSecSuccess && [items count] > 0) {
				NSDictionary *pkcsDict = [items objectAtIndex:0];
				// Get the SecIdentityRef
				SecIdentityRef identity = (SecIdentityRef)[pkcsDict objectForKey:(id)kSecImportItemIdentity];
				NSDictionary *op = [NSDictionary dictionaryWithObjectsAndKeys:
				                        (id)identity, kSecValueRef,
				                        kCFBooleanTrue, kSecReturnPersistentRef, nil];
				NSData *data = nil;
				err = SecItemAdd((CFDictionaryRef)op, (CFTypeRef *)&data);
				if (err == noErr && data != nil) {
						Identity *ident = [[Identity alloc] init];
						ident.persistent = data;
						ident.userName = @"Tukoff";
						[Database storeIdentity:ident];
						[ident release];
						NSLog(@"Stored identity...");
				// This happens when a certificate with a duplicate subject name is added.
				} else if (err == noErr && data == nil) {
					ShowAlertDialog(@"Unable to add identity",
									@"The certificate of the just-added identity could not be added to the certificate store because it "
									@"has the same name as a certificate already found in the store.");
				}
			} else {
				ShowAlertDialog(@"Unable to import generated certificate",
								@"Mumble was unable to import the generated certificate into the certificate store.");
			}
		}

		dispatch_async(dispatch_get_main_queue(), ^{
			[[self navigationController] dismissModalViewControllerAnimated:YES];
		});
	});
}

- (void) nameChanged:(TableViewTextFieldCell *)firstNameField {
	[_identityName release];
	_identityName = [[firstNameField textValue] copy];
}

- (void) emailChangd:(TableViewTextFieldCell *)emailField {
	[_emailAddress release];
	_emailAddress = [[emailField textValue] copy];
}

#pragma mark -
#pragma mark IdentityCreationProgressView delegate

- (void) identityCreationProgressViewDidCancel:(IdentityCreationProgressView *)progressView {
//	[[self navigationController] popViewControllerUsingTransition:UIViewAnimationTransitionCurlUp];
	NSLog(@"Cancel not implemented.");
}

@end

