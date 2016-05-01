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

last_feed=$((`date +%s`))
#your account name
account=steempty

#min and max price (usd), to exit script for manual intervention
min_bound=0.25
max_bound=1.5

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

init_price=`get_price`

while true ; do
  #check price
  price=`get_price`
  echo "price: $price" 
  #check persentage
  price_diff=`echo "scale=3;${price}-${init_price}" | bc`
  price_percentage=`echo "scale=3;${price_diff}/${init_price}*100" | bc | tr -d '-'`
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
    curl -H "content-type: application/json" -X POST -d "{\"method\":\"publish_feed\",\"params\":[\"${account}\",{\"base\":\"${price} SBD\",\"quote\":\"1.000 STEEM\"},true],\"jsonrpc\": \"2.0\",\"id\":0}" localhost:8091
    relock
  fi
  echo "${price_percentage}% | price: $price | time since last post: $update_diff"
  sleep $(($RANDOM%60))m
done
