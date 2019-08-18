## Twitter Manager
Internally, multiple arrays of tweets. Each array is a list of contiguous tweets, ordered in timeline order. 

Will need to work with UI and have an anchor object, which could be a tweet, a hashtag, a mention string, or a search string.

## Seamail Manager
Mostly, an array of SeamailThreads. 

## Forums Manager

## User Manager
LOGOUT! Need to figure out what data is user-specific, so we can uncache it at logout time.
	- All seamail gets reaped
	- Twittar searches may need to be removed; 
	- I think the image cache is okay -- as long as the app doesn't provide a way to get at images the current user can't see.
	- Forums may need to reap info about new post counts/last viewed times.
	- 

Anyway. Dict of users, indexed by username. Core Data stores all users as LoggedInUser, a subclass of KrakenUser. However,
we only create LoggedInUser objects for the actual logged-in user (for everyone else we create KrakenUser). This way,
the private data for a different logged-in user is inaccessible, even though CoreData is storing it.

## Event Manager

Filters
	- Right Now (events currently running)
	- Future Soon (events starting 'soon' -- start date > now, advance by half hours until we collect 5+ events?)
	- Tomorrow, (and today?), for planning the next day's favorites.
	- On a particular day?
	- Following/Notification Set, to show stuff you've tagged
	- Events in a particular room?
	- Events that are event-like (30-90 mins in length) not open-all-day-like (such as the boardgames area 'event')
	- Search by name
	- Official/Shadow?
	

## Image Manager
Cache images. Luckily, it appears that photo IDs can be created and deleted but the photo data for an id cannot be changed.

## Search Manager

## Settings

	- Network state -> connected to server, server addr text field
	- Login state/ Who is logged in
	- Saved Content to Post 
		- This is content the user created while offline (that is--onshore, mostly)
		- Tweets, posts, seamails, faves, follows, reactions, Profile Edits, personal comments
		- Not going to use SaveForLater with login, password change, password reset.
		- Nor will it work with admin functions.
	- Time Zone Info
		- Does server time match phone time?
		- If not, what do we show? 
	- Preference Settings
		- ??
	- Clear Cache


# UI
Tabs:
	Twittar
	Forums
	Seamail
	Info
		Deck Maps 
			AR Ship
		Code of Conduct
		Karaoke
		Profile
			PirateVision
			
	Now
		Announcements
		Notifications	
		Current events
		starred upcoming events
		
	Search ?
		Announcements

# Login
UI is an interstitial, mostly. 
	- Post to twittar or forums
	- entire Seamail tab
	- login in Info tab?
