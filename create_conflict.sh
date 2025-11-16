#!/bin/bash

[ -d ./conflict-test/ ] && rm -rf ./conflict-test/

mkdir conflict-test

cd conflict-test || exit

jj git init
jj describe -m 'initial'

touch conflicted.lua

echo "local value = 1 + 1" > conflicted.lua

jj new
jj describe -m 'change conflicted.lua'

echo "local value = 1 - 1" > conflicted.lua

jj new -r 'description("initial")'
jj describe -m 'change conflicted.lua to create conflict'

cat > conflicted.lua<< EOF
local value = 5 + 7
print(value)
print(string.format("value is %d", value))
EOF

jj new -r 'description("change conflicted.lua")'
jj describe -m 'commit contains conflicts'
