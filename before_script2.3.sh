#!/bin/bash

set -ex

# The Psych YAML parser has a bug where `[:foo]` fails to parse
sed -Ei $'s/    order: \[ :year, :month, :day \]/    order:\\\n      - :year\\\n      - :month\\\n      - :day/g' "$(bundle show activesupport)"/lib/active_support/locale/en.yml
bundle exec rake db:create
bundle exec rake db:migrate
