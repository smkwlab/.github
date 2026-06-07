#!/bin/bash
# Throwaway file to exercise the Claude review path. Deleted with the test PR.

target=$1

# Intentionally questionable code to invite review comments:
if [ $target = "prod" ]; then
  echo "Deploying to $target"
  rm -rf /tmp/$target/*
fi
