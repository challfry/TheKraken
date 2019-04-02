## Twitter Manager
Internally, multiple arrays of tweets. Each array is a list of contiguous tweets, ordered in timeline order. 

Will need to work with UI and have an anchor object, which could be a tweet, a hashtag, a mention string, or a search string.

## Seamail Manager
Mostly, an array of SeamailThreads. 

## Forum Manager

## User Manager
LOGOUT! Need to figure out what data is user-specific, so we can uncache it at logout time.
	- All seamail gets reaped
	- Twittar searches may need to be removed; 
	- I think the image cache is okay -- as long as the app doesn't provide a way to get at images the current user can't see.
	- Forums may need to reap info about new post counts/last viewed times.
	- 

Anyway. Dict of users, indexed by username.

## Event Manager

## Image Manager
Cache images. Luckily, it appears that photo IDs can be created and deleted but the photo data for an id cannot be changed.

## Search Manager


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
