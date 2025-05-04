	#!/bin/zsh
	# save as ci_scripts/ci_post_xcodebuild.sh in your project root
	 
	if [[ -d "$CI_APP_STORE_SIGNED_APP_PATH" ]]; then
	    TESTFLIGHT_DIR_PATH=../TestFlight
	    mkdir $TESTFLIGHT_DIR_PATH
	    git fetch --deepen 3 && git log -3 --pretty=format:"%s" | cat > $TESTFLIGHT_DIR_PATH/WhatToTest.en-US.txt
	fi
