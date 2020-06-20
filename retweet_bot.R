# Load in filter rules and basic parameters.
# A sample (blanked-out) config file is available in this repo.
source("config.R")

library(rtweet)

# for logging a timestamp for influx
options(digits = 19)

# search_strings is defined in config.R -- a vector of
# queries to pull down (in the format "#hashtag -filter:replies")
avail_tweets <- rtweet::search_tweets2(search_strings, include_rts = FALSE)

# read the timestamp from the last run of the script, and write the current
# time, to ensure you only process each tweet once
# if no "last run", just go for the last 5 minutes
last_run <- tryCatch(readLines("run_stamp.txt"),
  error = function(e) {
    return(Sys.time() - 300)
  }
)
writeLines(as.character(Sys.time()), "run_stamp.txt")

# we'll use the count of hashtags and @ signs as a filtering step later
avail_tweets$nhash <- strsplit(avail_tweets$text, "#")
avail_tweets$nat <- strsplit(avail_tweets$text, "@")

# drop anyone who's being spammy
# since search_tweets only goes back a little more than a week, this serves as a
# "temporary time-out" for any account posting too frequently
#
# note that permitted is defined in config.R and used to skip checks throughout
#
# for the ecology_tweets use-case, this basically is because I'm not about to
# decide that the UN used too many hashtags or the WWF posts too much
too_frequent <- names(table(avail_tweets$user_id)[table(avail_tweets$user_id) > spam_cutoff])
too_frequent_index <- avail_tweets$user_id %in% too_frequent[!(too_frequent %in% permitted)]
not_tweeting_that <- cbind(
  avail_tweets[too_frequent_index, ],
  reason = rep(
    "spam", # these reason codes are used in monitoring
    sum(too_frequent_index)
  )
)
avail_tweets <- avail_tweets[!(too_frequent_index), ]

# filter down to just new tweets
# (since we define spam on the full list retrieved by search_tweets)
avail_tweets <- avail_tweets[avail_tweets$created_at > last_run, ]
not_tweeting_that <- not_tweeting_that[not_tweeting_that$created_at > last_run, ]

# drop the ban list defined in config.R
# (for ecology_tweets, this is mostly oil companies & pseudoscience)
banned_index <- avail_tweets$user_id %in% banlist
not_tweeting_that <- rbind(
  not_tweeting_that,
  cbind(avail_tweets[banned_index, ],
    reason = rep(
      "ban",
      sum(banned_index)
      )
    )
  )
avail_tweets <- avail_tweets[!(banned_index), ]

# drop accounts with fewer than a set number of followers (in config.R)
# there's a lot of bot traffic on twitter. this cuts down on that.
# I personally set it to a level that my grandmother would get in 5 days
follower_index <- !(avail_tweets$followers_count > follower_cutoff) &
  !(avail_tweets$user_id %in% permitted)
not_tweeting_that <- rbind(
  not_tweeting_that,
  cbind(
    avail_tweets[follower_index, ],
    reason = rep(
      "followers_rule",
      sum(follower_index)
    )
  )
)
avail_tweets <- avail_tweets[!follower_index, ]

# drop a list of banned tweet sources (defined in config.R)
# this is the second most common way I filter out spam -- a lot of 
# "news aggregator" twitter accounts (which add noise without signal)
# use the same 6-7 apps to post (which no real human uses)
source_index <- avail_tweets$source %in% banned_sources &
  !(avail_tweets$user_id %in% permitted)
not_tweeting_that <- rbind(
  not_tweeting_that,
  cbind(
    avail_tweets[source_index, ],
    reason = rep(
      "source_app",
      sum(source_index)
    )
  )
)
avail_tweets <- avail_tweets[!source_index, ]

# drop people who use too many hashtags (as defined in config.R)
# for the areas ecology_tweets is interested in, there are a _ton_ of people
# who post a single sentence, a link to the Guardian, and 80 hashtags.
# that's not what we're here for.
hashtag_index <- vapply(avail_tweets$nhash, function(y) length(y), numeric(1)) >= hashtag_cutoff &
  !(avail_tweets$user_id %in% permitted)
not_tweeting_that <- rbind(
  not_tweeting_that,
  cbind(
    avail_tweets[hashtag_index, ],
    reason = rep(
      "hashtags",
      sum(hashtag_index)
    )
  )
)
avail_tweets <- avail_tweets[!(hashtag_index), ]

# and last but not least, drop people who @ too many people
# it is very, very rare for a tweet to exhibit this spam-signal and not 
# the hashtag spam signal
# as ever, at_cutoff is in config.R
at_index <- vapply(avail_tweets$nat, function(y) length(y), numeric(1)) >= at_cutoff &
  !(avail_tweets$user_id %in% permitted)

not_tweeting_that <- rbind(
  not_tweeting_that,
  cbind(
    avail_tweets[at_index, ],
    reason = rep(
      "atting",
      sum(at_index)
    )
  )
)
avail_tweets <- avail_tweets[!at_index, ]

# prepping for logging -- we want to make sure we log a 0 for each rule
# when it didn't filter any tweets
rule_levels <- c("atting", "spam", "ban", "hashtags", "followers_rule", "source_app")
rule_table <- table(factor(not_tweeting_that$reason, levels = rule_levels))
# Write to a logfile for Telegraf to tail and send to Influx
# This logs using Influx line protocol
# You could argue for having the rule levels as tags and writing these as 
# separate metrics, but at this scale I think limiting the complexity is better
write(paste0(
  "metatweet,acct=",
  acct_name, # config.R
  " followers=",
  nrow(rtweet::get_followers(acct_name)),
  ",n_rtweets=",
  nrow(avail_tweets),
  ",n_filtered=",
  nrow(not_tweeting_that),
  paste0(
    mapply(
      function(x, y) paste0(",", x, "=", y), 
      x = names(rule_table), 
      y = rule_table
      ), 
    collapse = ""),
  " ",
  as.numeric(Sys.time()) * 1e9 # UNIX timestamp in nanoseconds
),
"ecotweet.log",
append = TRUE
)

# I like to save my output tweets to refine filter rules against
write.table(
  not_tweeting_that[!(sapply(not_tweeting_that, class) == "list")], 
  "filtered_tweets.csv", 
  append = TRUE, 
  sep = ",", 
  col.names = FALSE
  )
write.table(
  avail_tweets[!(sapply(avail_tweets, class) == "list")], 
  "output_tweets.csv", 
  append = TRUE, 
  sep = ",", 
  col.names = FALSE
  )

# post the tweets!
if (nrow(avail_tweets) > 0) {
  lapply(avail_tweets$status_id, function(x) rtweet::post_tweet(retweet_id = x))
}

# print to stdout to show up in journalctl logs
# nice easy validation that the thing is working
print("Script complete")
