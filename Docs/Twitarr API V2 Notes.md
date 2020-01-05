
# Seamail
GET /api/v2/seamail
GET /api/v2/seamail_threads
GET /api/v2/seamail/:id_string
POST /api/v2/seamail											New seamail thread, with initial message
POST /api/v2/seamail/:id										Add message to existing thread
POST /api/v2/seamail/:id/recipients								Disabled? Modifies recipient list.
GET /api/v2/user/new_seamail

# Twitter Stream
GET /api/v2/stream or /api/v2/stream/:start						Get the tweets in the stream.
GET /api/v2/thread/:id											Get details of a stream post (tweet) with the given :id
GET /api/v2/stream/m/:query									View a mentions stream. 
GET /api/v2/stream/h/:query									View a hash tag tweet stream.
POST /api/v2/stream											Creates a new tweet in the tweet stream.
GET /api/v2/tweet/:id											Gets a single tweet.
POST /api/v2/tweet/:id											Allows the user to edit the text or photo for this post. 
DELETE /api/v2/tweet/:id										Allows the user to delete a post.
POST /api/v2/tweet/:id/locked/:locked							Changes locked status for a stream post and its children. 
POST /api/v2/tweet/:id/react/:type								React to a post. 
DELETE /api/v2/tweet/:id/react/:type								Remove reaction from a post.
GET /api/v2/tweet/:id/react										Get the list of reactions that have been applied to a post

# Photos
GET /api/v2/photo												Gets a list of images that have been uploaded to the server.
POST /api/v2/photo											Upload a photo.
GET /api/v2/photo/:photo_id									gets photometa for the given photo id.
DELETE /api/v2/photo/:photo_id
GET /api/v2/photo/small_thumb/:photo_id							These return actual image data.
GET /api/v2/photo/medium_thumb/:photo_id
GET /api/v2/photo/full/:photo_id

# Hashtags
GET /api/v2/hashtag/ac/:query									Get auto completion list for hashtags. 
GET /api/v2/hashtag/repopulate									Completely rebuilds the table of hashtags.

# Search
GET /api/v2/search/all/:query									Perform a search against the database for results.
GET /api/v2/search/users/:query
GET /api/v2/search/seamails/:query
GET /api/v2/search/tweets/:query
GET /api/v2/search/forums/:query
GET /api/v2/search/events/:query

# Users
POST /api/v2/user/new										Create an account. Uses the reg code thing.
GET or POST /api/v2/user/auth									Log in.
GET or POST /api/v2/user/logout								Log out.
GET /api/v2/user/whoami or /api/v2/user/profile					Gets basic acct info for logged in user.
POST /api/v2/user/profile
POST /api/v2/user/change_password
POST /api/v2/user/reset_password
GET /api/v2/user/mentions										Returns # of mentions in tweets and forum posts.
GET /api/v2/user/ac/:query
GET /api/v2/user/profile/:username								Gets a user's profile. Includes 10 recent tweets by that user.
POST /api/v2/user/profile/:username/personal_comment
POST /api/v2/user/profile/:username/star
GET /api/v2/user/starred										Gets users starred by logged in user.
GET /api/v2/user/photo/:username
POST /api/v2/user/photo
DELETE /api/v2/user/photo
POST /api/v2/user/schedule

# Forums
GET /api/v2/forums/													Returns a page of forum threads.
POST /api/v2/forums													Creates a forum thread and its first post.
GET /api/v2/forums/:id													Returns a forum thread and its posts.
POST /api/v2/forums/:id												Creates a new post in the thread.
DELETE /api/v2/forums/:id												Deletes an entire forum thread. Mods only.
POST /api/v2/forum/:id/sticky/:sticky										Changes sticky status for a forum thread. Admin only.
POST /api/v2/forum/:id/locked/:locked									Changes locked status for a forum thread. Mods only.
GET /api/v2/forums/:id/:post_id											Returns a single post from a forum thread.
POST /api/v2/forums/:id/:post_id										Edits a post in the thread.
DELETE /api/v2/forums/:id/:post_id										Deletes a post from a thread.
POST /api/v2/forums/:id/:post_id/react/:type								React to a post
DELETE /api/v2/forums/:id/:post_id/react/:type							Remove reaction from a forum post.
GET /api/v2/forums/:id/:post_id/react										Get the list of reactions that have been applied to a forum post
POST /api/v2/forum/mark_all_read										Marks all forums as read for the current user.

# Events
GET /api/v2/event														Returns a list of all events.
GET /api/v2/event/day/:epoch											Gets a list of all events with a start time on the same day as :epoch.
GET /api/v2/event/mine/:epoch											Gets a list of favorited events with a start time on the same day as :epoch.
GET /api/v2/event/:id													Get details of an event.
GET /api/v2/event/:id/ical												Get details of an event as an ical file.
DELETE /api/v2/event/:id												Remove an event. Admins.
POST /api/v2/event/:id													Allows an admin to edit the title, description, location, start time, and end time of an event.
POST /api/v2/event/:id/favorite											Allows the user to favorite an event.
DELETE /api/v2/event/:id/favorite										Allows the user to remove their favorite from an event.

# Textfiles
GET /api/v2/text/:filename												Returns text for display to the user. 
GET /api/v2/time														Returns the server time.
GET /api/v2/reactions													Returns a list of valid reaction words.
GET /api/v2/announcements											Returns currently active announcements.

# Alerts
GET /api/v2/alerts														Returns the data for the user's current alerts, along with all active announcements.
GET /api/v2/alerts/check
POST /api/v2/alerts/last_checked										Allows a user to set their last_checked_time time to a specific value.

# Admin
GET /api/v2/admin/users
GET /api/v2/admin/users/:query
GET /api/v2/admin/user/:username/profile
POST /api/v2/admin/user/:username
POST /api/v2/admin/user/:username/activate DISABLED
POST /api/v2/admin/user/:username/reset_password
POST /api/v2/admin/user/:username/reset_photo
GET /api/v2/admin/user/:username/regcode
GET /api/v2/admin/announcements
POST /api/v2/admin/announcements
GET /api/v2/admin/announcements/:id
POST /api/v2/admin/announcements/:id
DELETE /api/v2/admin/announcements/:id
POST /api/v2/admin/schedule
GET /api/v2/admin/sections
POST /api/v2/admin/sections/:name
