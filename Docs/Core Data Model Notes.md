#  Notes on the Core Data Model 

## KrakenUser

Since the model layer models what we know about app state, and not the results of any one server call, KrakenUser contains
all the info that we can know about a user, even though most of the time we'll fill them in with UserInfo{} objects that have 3 fields.

Some data in User objects from the V2 service is specific to what the logged-in user has commented about the given User.
That data is modeled separately, in CommentsAndStars objects.

## LoggedInKrakenUser

A subclass of KrakenUser for the user that's currently logged in.

## PotentialUser

Used in Seamail thread creation, if the user types in a recipient name while offline. We can't verify whether the typed in value is 
an actual user, as we're offline, so we store the recipient as a PotentialUser.

## PhotoDetails

PhotoDetails models metadata that we get for an image, but not the image data itself. This could change.
It is probably okay to store small photos in the db; and I think CD can be configured to automagically build external file refs 
for larger photos and store larger photos there. 

Biggest downside to doing this is that we will probably need to delete cached photos to save space; it might be easier to just run
a traditional cache.

## TwitarrPost

if ContigWithOlder is FALSE, there may be posts on the server with timestamps between this post and the one preceding it in the cache.
If ContigWithOlder is TRUE, we're reasonably confident this post and the one in cache with the next earlier timestamp are contiguous.

Generally, any posts delivered to us from stream requests are considered contiguous (except the last one in a response). 

Only set contigWithOlder to FALSE when adding the post to the cache; if the post already existed in the cache and we're just updating
its contents, it can only transition from FALSE to TRUE.

// need to talk about parentChain

## CommentsAndStars

These are comments that the logged-in user has made about other users. isStarred is basically a one-bit comment.

loggedInUser is the user that made the comments. ONLY that user should see the comments. We have to handle the case where
multiple users log into the same device.

## Events

Besides all the stuff that comes from the server for events, we store:
	• the ekEventID if we've made an EventKit Calendar Item for this event
	• the localNotificationID if we've created a local Notificaiton for this event.
Both of these items are local to the device, but not tied to the current user.

Event objects also synthesize Date values for start end end times from the Epoch values.

## PostOperation

This is the root class for a bunch of content creation actions. Most of these actions eventually go over the network as a POST call.
Each op type knows how to build its POST from its data.
PostOperations can be edited and deleted before being sent to the server, although if the device is online they'll get sent as soon as they're created.

