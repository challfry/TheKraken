## Pirate Selfies
Basically a Face AR mode, with a pirate hat and eyepatch overlay.

## AR Boat View
Show the boat maps (the PDFs), stacked, in AR.
Show the user's approximate location using iBeacons.

## iBeacon Support
~100 beacons, distribute around ship
Probably need coordination from both THO and HAL 
Need server support to make an almanac of where each beacon is
Need pickup mode to retrieve beacons

## Local notifications
Tag events to send local notifications. Basically alarms for event times.

## Better time zone management
Notify when the device's time doesn't match server time.
Make it very clear whether times shown are device time or ship time when they don't match!

Tweets should get shown with "2min" or similar, and be time-corrected but otherwise ignore absolute time.
Seamail could give times as "2:34 PM device/1:34 PM boat" perhaps? (only when device doesn't match boat)
Calendar should also show both times.

## Offline mode
Most everything app has ever downloaded will be avail when not on HAL wifi.
App tells user at fg time that it's in offline mode, may offer help to join wifi?

When offline, we show content from caches. Duh. Network loads in the model just fail, and it must be okay.
Search calls to the model auto-magically search the cache instead of the server when offline.
That is, search is initiated by the UI telling the model to search something. The model may choose to do a local search if we're offline.
Results are still delivered async, UI doesn't know the search was local.

## Games?
Maybe we can combine AR and beacons to create shipboard game things?

## Event View improvements
Offline mode, especially so that events can be viewed onshore
Happening Now view
Maybe filter by location onboard?

## Inbound links
Make the app the handler for links, maybe? Universal links require the super-fun app site association file.
Custom url schemes are also a possibility.

