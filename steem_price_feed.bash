#!/bin/bash
last_feed=$((`date +%s`))
#your account name
account=steempty

#min and max price (usd), to exit script for manual intervention
min_bound=0.25
max_bound=1.5

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
    echo "sending feed ${price_percentage}% price: $price"
    curl -H "content-type: application/json" -X POST -d "{\"method\":\"publish_feed\",\"params\":[\"${account}\",{\"base\":\"${price} SBD\",\"quote\":\"1.000 STEEM\"},true],\"jsonrpc\": \"2.0\",\"id\":0}" localhost:8091
  fi
  echo "${price_percentage}% | price: $price | time since last post: $update_diff"
  sleep $(shuf -i 1-60 | head -1)m
done
