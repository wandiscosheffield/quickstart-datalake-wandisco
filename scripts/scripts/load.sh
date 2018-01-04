#!/bin/sh

# 2016 Quarter 1 data

curl https://s3.amazonaws.com/nyc-tlc/trip+data/green_tripdata_2016-01.csv | tail -n +2 > green_tripdata_2016-01.csv
sudo -H -u hadoop /usr/local/hadoop/bin/hadoop fs -copyFromLocal green_tripdata_2016-01.csv /user/sample/green_tripdata_2016-01.csv
rm green_tripdata_2016-01.csv

curl https://s3.amazonaws.com/nyc-tlc/trip+data/green_tripdata_2016-01.csv | tail -n +2 > green_tripdata_2016-02.csv
sudo -H -u hadoop /usr/local/hadoop/bin/hadoop fs -copyFromLocal green_tripdata_2016-02.csv /user/sample/green_tripdata_2016-02.csv
rm green_tripdata_2016-02.csv

curl https://s3.amazonaws.com/nyc-tlc/trip+data/green_tripdata_2016-01.csv | tail -n +2 > green_tripdata_2016-03.csv
sudo -H -u hadoop /usr/local/hadoop/bin/hadoop fs -copyFromLocal green_tripdata_2016-03.csv /user/sample/green_tripdata_2016-03.csv
rm green_tripdata_2016-03.csv