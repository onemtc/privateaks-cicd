#!/bin/sh
# sourced from https://brendanthompson.com/posts/2021/09/github-actions-self-hosted-runner-on-azure
# Create a folder
# mkdir actions-runner && cd actions-runner
mkdir /usr/local/ghagent && cd /usr/local/ghagent
# Download the latest runner package
curl -o actions-runner-linux-x64-2.299.1.tar.gz -L https://github.com/actions/runner/releases/download/v2.299.1/actions-runner-linux-x64-2.299.1.tar.gz
tar xzf ./actions-runner-linux-x64-2.299.1.tar.gz
# config
./config.sh --url https://github.com/expNYCLarryClaman/privateaks --token APISQCZDCEOFCHARXK4HPKLDORDVY  --unattended
# Last step, run it!
./svc.sh install
./svc.sh start


  'GHREPO=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance?api-version=2021-02-01" | jq -r .compute.userData)'
