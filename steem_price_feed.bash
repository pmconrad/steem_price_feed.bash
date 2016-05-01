#!/bin/bash

# Price feed logic according to Dan:
# Apr 27th
# dan
# 9:11 PM @clayop max frequency 1 hr, min frequency 7 days max change 3%
# 9:11 also introduce some randomness in your queries
# 9:11 that will prevent everyone from updating at the same time
# 9:12 err.. min change 3% :simple_smile:
# 9:12 you can pick what ever percent you want, these are just my opinion on how to minimize network load while still serving the purpose effectively
# 9:23 PM the range for manual intervention should be +/- 50%
# 9:32 PM +/- 50% of HARD CODED long term average
# 9:32 PM I don't think the safety nets should be a percent of a past value...
# 9:32 yes.. so right now between .0005 and .002 SATS
# 9:33 $0.25 and $1.50
# 9:33 something along those lines
# 9:33 if the price moves up we can manually adjust the feeds

#min and max price (usd), to exit script for manual intervention
min_bound=0.25
max_bound=1.5
wallet=http://127.0.0.1:8092/rpc

usage () {
    cat 1>&2 <<__EOU__
Usage: $0 -w|--witness <witness> [-m|--min <min-price>] [-M|--max <max-price>] [-r|--rpc-url <rpc-url>] [-v|--vote]
-w sets the name of the witness whose price will be set (and optionally voted
   from).
-m and -M set the absolute maximum and minimum acceptable price. This script
   will exit if the actual price exceeds these bounds. Defaults are $min_bound
   and $max_bound, respectively.
-r specifies the cli_wallet's HTTP-RPC URL. The default is $wallet.
-v will make the given witness vote for the creators of this script, i. e.
   cyrano.witness and steempty. If you have already voted you'll see an error
   message if you vote again. That can be ignored.

Hint: for slightly better security you should keep the cli_wallet locked at all
times. In order to vote, this program needs to unlock the wallet. For this,
create a file named "lock" in the current directory with read permission only
for yourself, and paste the following JSON-RPC command into the "lock" file:
{"id":0,"method":"unlock","params":["<your_password>"]}
Obviously, you need to replace the placeholder with your actual password.
__EOU__
    exit 1
}

unlock () {
    if [ -r lock ]; then
	echo -n "Unlocking wallet..."
	curl -s --data-ascii @lock "$wallet"
	echo ""
    fi
}

relock () {
    if [ -r lock ]; then
	echo -n "Re-locking wallet..."
	curl -s --data-ascii '{"id":0,"method":"lock","params":[]}' "$wallet"
	echo ""
    fi
}

vote () {
    unlock
    curl -s --data-ascii '{"method":"vote_for_witness","params":["'"$account"'","cyrano.witness",true,true],"jsonrpc":"2.0","id":0}' "$wallet"
    curl -s --data-ascii '{"method":"vote_for_witness","params":["'"$account"'","steempty",true,true],"jsonrpc":"2.0","id":0}' "$wallet"
    relock
}

while [ $# -gt 0 ]; do
    case "$1" in
	-w|--witness) account="$2";   shift; ;;
	-m|--min)     min_bound="$2"; shift; ;;
	-M|--max)     max_bound="$2"; shift; ;;
	-r|--rpc-url) wallet="$2";    shift; ;;
	-v|--vote)    vote=yes;       ;;
	*)	      usage;	      ;;
    esac
    shift
done

if [ -z "$account" ]; then usage; fi
if [ "$vote" = yes ]; then vote; fi

# Avoid problems with decimal separator
export LANG=C

get_wallet_price () {
    curl --data-ascii '{"id":0,"method":"get_witness","params":["'"$account"'"]}' \
	 -s "$wallet" \
      | sed 's=[{,]=&\
=g' \
      | grep -A 2 'sbd_exchange_rate' \
      | grep '"base"' \
      | cut -d\" -f 4 \
      | sed 's= SBD==;s= STEEM=='
}

get_last_update () {
    local jtime="$(curl --data-ascii '{"id":0,"method":"get_witness","params":["'"$account"'"]}' \
			-s "$wallet" \
		     | sed 's=[{,]=&\
=g' \
		     | grep '"last_sbd_exchange_update"' \
		     | cut -d\" -f 4 \
		     | sed 's= SBD==;s= STEEM==')"
    date --date "${jtime}Z" +%s
}

function get_price {
  while true ; do
    price=$(printf '%.*f\n' 3 `curl https://www.cryptonator.com/api/ticker/steem-usd 2>/dev/null| cut -d"," -f3 | cut -d"\"" -f4 `)
    #price source and way to calculate will probably need to be changed in the future
    if [[ $price = *[[:digit:]]* ]] ; then
      break
    fi
    sleep 1m
  done
  echo $price
}

init_price="`get_wallet_price`"
if [ "$init_price" = "" ]; then
    echo "Empty price - wallet not running?" 1>&2
    exit 1
fi
last_feed="`get_last_update`"

while true ; do
  #check price
  price=`get_price`
  echo "price: $price" 
  if [ "$price" = 0.000 ]; then
    echo "Zero price - ignoring"
    price="$init_price"
  fi
  #check persentage
  price_diff=`echo "scale=3;${price}-${init_price}" | bc`
  price_percentage=`echo "scale=3;${price_diff}/${price}*100" | bc | tr -d '-'`
  now=`date +%s`
  update_diff=$(($now-$last_feed))
  #check bounds, exit script if more than 50% change, or minimum/maximum price bound
  if [ `echo "scale=3;$price>$max_bound" | bc` -gt 0 -o `echo "scale=3;$price<$min_bound" | bc` -gt 0 ] ; then
     echo "manual intervention (bound) $init_price $price, exiting"
     exit 1
  fi 
  if [ `echo "$price_percentage>50" | bc` -gt 0 ] ; then
     echo "manual intervention (percent) $init_price $price, exiting"
     exit 1
  fi 
  #check if to send update (once an hour maximum, 3% change minimum)
  if [ `echo "$price_percentage>3" | bc` -gt 0 -a $update_diff -gt 3600 ] ; then
    init_price=$price
    last_feed=$now
    unlock
    echo "sending feed ${price_percentage}% price: $price"
    curl -H "content-type: application/json" -X POST -d "{\"method\":\"publish_feed\",\"params\":[\"${account}\",{\"base\":\"${price} SBD\",\"quote\":\"1.000 STEEM\"},true],\"jsonrpc\": \"2.0\",\"id\":0}" "$wallet"
    relock
  fi
  echo "${price_percentage}% | price: $price | time since last post: $update_diff"
  sleep $(($RANDOM%60))m
done
