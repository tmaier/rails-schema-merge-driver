#!/bin/sh

set -e

echo "# Configure git"
git config --global --add safe.directory "$PWD"

echo "# Install gems"
bundle install
