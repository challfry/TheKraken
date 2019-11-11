## Pirate Selfies
Basically a Face AR mode, with a pirate hat and eyepatch overlay.

## AR Boat View
Show the boat maps (the PDFs), stacked, in AR.
Show the user's approximate location using iBeacons.

## iBeacon Support
~100 beacons, distribute around ship
Probably need coordination from both THO and HAL 
Need server support to make an almanac of where each beacon is
Need drop mode to install beacons - tells server where beacon is (room name) and its ID
Need pickup mode to retrieve beacons

## Local notifications
Tag events to send local notifications. Basically alarms for event times.

Call /api/v2/alerts once a minute? 
	- Tweets Tab - badge with # tweet_mentions
	- Forums Tab - badge with # of forum_mentions
	- Seamail Tab - badge with # unread_seamail
	- Events Tab - Maybe badge this?
	 

## Better time zone management
Notify when the device's time doesn't match server time.
Make it very clear whether times shown are device time or ship time when they don't match!

Tweets should get shown with "2min" or similar, and be time-corrected but otherwise ignore absolute time.
Seamail could give times as "2:34 PM device/1:34 PM boat" perhaps? (only when device doesn't match boat)
Calendar should also show both times.

Note that there's 6 cases at play here:
	1. Time and timezone match, show 1 time
	2. Times differ, same timezone. Estimate difference between server and device time using /api/v2/time, show both if offset > 20 mins
	3. Different timezones, same time, timezones have same offset. This can happen with EDT and AST. Only need to show one time,
		but need to be careful that time calculations from epoch use server tz, not device tz.
	4. Different timezones, same time. (e.g. EST/AST) User probably updated time instead of changing zone. Only need to show one time,
		but need to be careful that time calculations from epoch use server tz, not device tz.
	5. Different timezones, different times, offset matches tz offset. Device time is 'right', just in a different TZ than server. Show both.
	6. Different TZ, different times, offset doesn't match tz offset. Weep for humanity, show both times by calculating offset from server
		to device. 

## Offline mode
Most everything app has ever downloaded will be avail when not on HAL wifi.
App tells user at fg time that it's in offline mode, may offer help to join wifi?

When offline, we show content from caches. Duh. Network loads in the model just fail, and it must be okay.
Search calls to the model auto-magically search the cache instead of the server when offline.
That is, search is initiated by the UI telling the model to search something. The model may choose to do a local search if we're offline.
Results are still delivered async, UI doesn't know the search was local.

## Games?
Maybe we can combine AR and beacons to create shipboard game things?

Chaos Engine, where players get randomly paired and must find each other. Once the server pairs, players start receiving updates
about each others' shipboard loc (via beacons). Paired players moving phones close to each other scores the points.

AR Pokemon Go -- distribute QR code paper around ship, scan to see pokemon and take picture?

## Event View improvements
Offline mode, especially so that events can be viewed onshore
Happening Now view
Maybe filter by location onboard?
Daily buttons, with a # of favorited events for each day, so users can see what days to do planning for.

## Inbound links
Make the app the handler for links, maybe? Universal links require the super-fun app site association file.
Custom url schemes are also a possibility.

## Twitarr, Seamail, Forums improvements
Rotate phone to show in a fullscreen view the topmost photo in a tweet/mail/forum post that's on screen.

## One Weeks Later
Choose one twitarr post the user made each day, offer to share that post to Twitter (the blue bird Twitter, by Twitter.com)
exactly one week after originally posting it. Since the first twitarr posts are likely to happen around noon Sat, this means that repost
notificaitons would start popping up around noon the next Sat., a few hours after everyone is done disembarking.

I think we'd use TwitterKit 3 to power this? Dunno. Anyway, it probably works internally by setting a local notification with a one week
timer every day the user posts to twitarr. When the timer fires we look back at the posts the user made 7 days ago and pick the one with
the most likes, with a +modifier for posts with pictures and a -modifier for posts with curse words. Might also need to filter out twitarr 
posts that are too long for Twitter. Anyway, we post a local notification suggesting this post be reposted to Twitter 7 days after it happened, 
with a "#jococruise" hashtag likely attached (or something).

One notification max per day, don't send notifications between 10:00 PM and 8:00 AM local time, have an option in Settings to turn it off.
This also means that at most one post per day gets reposted per user.

## Dark Mode, Dynamic Type

Bread and butter features. But, I want to implement them with traversing view stylers. 
