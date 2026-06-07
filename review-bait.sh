#!/bin/bash
# Throwaway file to verify the lightweight Claude review. Deleted with the test PR.

target=$1

# Intentionally questionable code to invite review comments:
if [ $target = "prod" ]; then
  echo "Deploying to $target"
  rm -rf /tmp/$target/*
fi
