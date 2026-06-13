#!/bin/bash
tail -n +2 /mnt/Users.csv | while IFS=';' read -r firstName lastName _ _ ou _ _ _ _ password
do
  if ! samba-tool ou list | grep -q "OU=$ou"; then
  samba-tool ou create "OU=$ou"
  fi
  samba-tool user create "${firstName}${lastName}" "$password" \
  --userou="OU=$ou"
done
