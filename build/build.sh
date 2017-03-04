#!/bin/bash
set -e # Any subsequent(*) commands which fail will cause the shell script to exit immediately

if [[ $TRAVIS_PULL_REQUEST == "false" ]]
then
	openssl aes-256-cbc -pass pass:$ENCRYPTION_PASSWORD -in $BUILD_DIR/pubring.gpg.enc -out $BUILD_DIR/pubring.gpg -d
	openssl aes-256-cbc -pass pass:$ENCRYPTION_PASSWORD -in $BUILD_DIR/secring.gpg.enc -out $BUILD_DIR/secring.gpg -d
	openssl aes-256-cbc -pass pass:$ENCRYPTION_PASSWORD -in $BUILD_DIR/deploy_key.pem.enc -out $BUILD_DIR/deploy_key.pem -d

	eval "$(ssh-agent -s)"
	chmod 600 $BUILD_DIR/deploy_key.pem
	ssh-add $BUILD_DIR/deploy_key.pem
	git config --global user.name "TraneIO CI"
	git config --global user.email "ci@trane.io"
	git config --global push.default matching
	git remote set-url origin git@github.com:traneio/future.git
	git fetch --unshallow
	git checkout master || git checkout -b master
	git reset --hard origin/master

	if [ -e "release.version" ] && [ $TRAVIS_BRANCH == "master" ]
	then
		echo "Performing a release..."
		git rm release.version
		git commit -m "[skip ci] [release] remove release.version"
		git push

		mvn -B clean release:prepare --settings build/settings.xml -DreleaseVersion=$(cat release.version)
		mvn release:perform javadoc:javadoc --settings build/settings.xml

        DOCS_PATH=docs/api/future-java/$(cat release.version)

		rm -rf $DOCS_PATH
		mkdir -p $DOCS_PATH
		cp -r future-java/target/site/apidocs/* $DOCS_PATH

		git add .
		git commit -m "[skip ci] update javadocs"
		git push

	elif [[ $TRAVIS_BRANCH == "master" ]]
	then
		echo "Publishing a snapshot..."
		mvn clean org.jacoco:jacoco-maven-plugin:prepare-agent package sonar:sonar deploy javadoc:javadoc --settings build/settings.xml
		
		DOCS_PATH=docs/api/future-java/$(echo -e 'setns x=http://maven.apache.org/POM/4.0.0\ncat /x:project/x:version/text()' | xmllint --shell pom.xml | grep -v /)
        
		rm -rf $DOCS_PATH
		mkdir -p $DOCS_PATH
		cp -r future-java/target/site/apidocs/* $DOCS_PATH

		git add .
		git commit -m "[skip ci] update javadocs"
		git push

	else
		echo "Publishing a branch snapshot..."
		mvn clean versions:set -DnewVersion=$TRAVIS_BRANCH-SNAPSHOT org.jacoco:jacoco-maven-plugin:prepare-agent package sonar:sonar deploy --settings build/settings.xml 
	fi
else
	echo "Running build..."
	mvn clean org.jacoco:jacoco-maven-plugin:prepare-agent package sonar:sonar
fi