# Note that all values in this config are set to not filter anything
# You'll have to find the proper filtering levels for your application
acct_name <- "your_bot"

# Any tweets matching strings in here are fair game for retweeting
# For ecology_tweets, these are all in the format:
# #hashtag -filter:replies
search_strings <- c(
  
)

# List of user IDs to never, ever retweet
banlist <- c(

)

# List of user IDs who are exempt from all checks
permitted <- c(

)

# List of tweet sources to filter out
# There are some specific enterprise softwares with twitter integrations
# whose users are generally pretty spammy
banned_sources <- c(

)

# Numeric cutoffs for annoying behaviors
# These values effectively set the checks to "off" 
spam_cutoff <- 9999
follower_cutoff <- -1
hashtag_cutoff <- 281
at_cutoff <- 281
