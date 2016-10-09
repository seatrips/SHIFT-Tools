#!/bin/bash

wget https://github.com/viper-tkd/SHIFT-Tools/archive/master.zip
unzip master.zip
mv SHIFT-Tools-master/*.sh .
rm -rf SHIFT-Tools-master/
rm master.zip
