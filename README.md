# R code for a generic retweet-bot

## What is this?

This script and configuration file will do the following:

* Search Twitter and retrieve tweets on a subject of interest
* Automatically run those tweets through a set of filtering rules to try and reduce spam
* Retweet the tweets which your rules haven't marked spam
* Write the spam and ham tweets to separate files and log a handful of metrics to a file in InfluxDB line protocol.

The code here has been fully genericized -- none of the configuration options should filter any tweets out, and there's no search strings provided to actually search with. This should make it easier to use this code for other bots.

This code (with some carefully-considered configuration values) is what currently powers 
[ecology_tweets](https://twitter.com/ecology_tweets).

## Why would I want to do this?

Personally, I wanted to get a better sense of what people in ecology and conservation were thinking and talking about, and maybe make it easier for other people to get their message out there. I also had really appreciated the (non-automated!) retweeting on the #rstats hashtag (as well as the automated #statstwitter and #plottertwitter), so decided to make a bot to do similar. 

A challenge of retweeting ecology-related hashtags, however, is that there's a lot more spam (and outright dangerous or hateful content) in the environmental arena than in the relatively-niche #statstwitter or #plottertwitter spaces. I personally didn't want to get involved in direct content filtering (both because I don't consider myself qualified to do so and because keeping a content filter updated would be a full time job -- it's currently June 2020, and from Australian wildfires to COVID-19 to murder hornets and on, there have been a lot of trends in ecology twitter with new flavors of spam to match), so I tried to find other parameters that could filter out spam while staying agnostic about the content.

## So all I need is this code?

Kinda. You're also going to need a token for Twitter's API (and an account to post with); [this vignette](https://rtweet.info/articles/auth.html) walks through that process.

You'll also need to schedule the script somehow -- the script as it stands doesn't loop at all, and using long-running R processes (such as wrapping the post script in a while loop with a `Sys.sleep` call) can get pretty messy due to memory fragmentation. I personally run ecology_tweets using a small bash script:

```bash
while true; do
    Rscript run_bot.R
    sleep 900
done
```

And then have that script managed by a small systemd service:
```
[Unit]
After=network.target

[Service]
WorkingDirectory=/home/pi/ecotweet
ExecStart=/usr/local/bin/ecotweet.sh
Restart=Always
RestartSec=600

[Install]
WantedBy=default.target
```

Finally, though it's not required by any means, I personally have a [Telegraf/Influx/Grafana](https://www.mm218.dev/2020/05/tig-on-pi/) stack set up to track the number of tweets that are being filtered and for what reason (plus how many followers the bot has). I use this to fine-tune the filter rules over time; you might find a different method that works better for you.

## Miscellanea

Other than R, this code's only dependency is the [rtweet](https://rtweet.info/) package. If you're running this script through a shell script, you'll want to make sure rtweet is installed in your system library (`sudo R -e "install.packages('rtweet')"` on Linux). 

rtweet in turn has 79 dependencies, many of which require c and c++ compilation. This can require a lot of system resources; if you're trying to set up a bot on a resource-limited server, it's probably easiest to build the bot inside a docker container on a stronger system and then deploy the container rather than attempting to compile the various libraries.
