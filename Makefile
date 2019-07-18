.PHONY: clean test lint build

SHELL := /bin/bash
PATH := ./node_modules/.bin:$(PATH)
NPM_REGISTRY=https://artifactory.corp.adobe.com:443/artifactory/api/npm/npm-react-release/
SERVER=root@react-spectrum.corp.adobe.com

all: node_modules

node_modules: package.json
	yarn install
	touch $@

# using this won't generate icons and definitions, but will allow us to run things like cleaning beforehand
install_no_postinstall:
	NOYARNPOSTINSTALL=1 yarn install

# --ci keeps it from opening the browser tab automatically
run:
	NODE_ENV=storybook start-storybook -p 9002 --ci -c ".storybook-v2"

run_3:
	NODE_ENV=storybook start-storybook -p 9003 --ci -c ".storybook-v3"

clean:
	yarn clean:icons
	rm -rf dist storybook-static storybook-static-v3 public src/dist
	$(MAKE) clean_docs

clean_all:
	$(MAKE) clean
	$(MAKE) clean_node_modules

clean_node_modules:
	$(MAKE) clean_project_node_modules
	$(MAKE) clean_docs_node_modules

clean_project_node_modules:
	rm -rf node_modules
	rm -rf packages/*/*/node_modules

# --prefix needs to come before the command that npm is to run, otherwise documentation seems to indicate that it will write node_modules to that location
docs:
	cd documentation && yarn --no-lockfile
	cd documentation && yarn build

docs_local:
	cd documentation && yarn --no-lockfile
	cd documentation && yarn develop

clean_docs:
	rm -rf documentation/public

# in order to pick up new changes to local components, this should be run before `docs_local` or `docs`
clean_docs_node_modules:
	rm -rf documentation/node_modules

lint:
	npm run check-types
	eslint src test stories
	eslint packages --ext .js,.ts,.tsx

test:
	NODE_ENV=test mocha

jest_test:
	NODE_ENV=test jest

cover:
	NODE_ENV=test BABEL_ENV=cover nyc mocha

jenkins_test: lint
	NODE_ENV=test jest
	# Test in React 15
	NOYARNPOSTINSTALL=1 yarn install-peerdeps --yarn enzyme-adapter-react-15 --extra-args "--ignore-workspace-root-check"
	NODE_ENV=test mocha

	# Test latest and generate coverage report
	yarn install-peerdeps --yarn enzyme-adapter-react-16 --extra-args "--ignore-workspace-root-check"
	NODE_ENV=test BABEL_ENV=cover nyc --reporter cobertura --report-dir . mocha $(MOCHA_OPTS) --reporter mocha-junit-reporter; \
	find ./node_modules/ -name coverage.json -exec rm {} \; ;\

build:
	rm -rf dist src/dist
	cp -R src dist
	cp -R node_modules/@adobe/spectrum-css/dist/components dist/spectrum-css
	cp -R spectrum-css-overrides dist/spectrum-css-overrides
	find dist/spectrum-css -name colorStops -exec rm -rf {} +;
	BUILD_ENV=production babel dist -d dist
	find dist \( -name index.styl -o -name "Shell*.styl" \) -exec bash -c 'f="{}"; o=$$(dirname $${f%.styl}.css); stylus --use ./bin/compile-stylus.js $$f -o $$o' \;
	find dist -name "*.styl" -delete
	find dist -name "*.js" -exec sed -i.bak 's/index.styl/index.css/g' {} \;
	find dist -name "*.js" -exec sed -i.bak -E 's/(Shell.*\.)styl/\1css/g' {} \;
	find dist -name "*.bak" -delete
	cp -R node_modules/@adobe/focus-ring-polyfill dist/focus-ring-polyfill
	cp -R node_modules/@react/react-spectrum-icons/dist/* dist/Icon/.
	cp src/package.json dist/package.json
	cp README.md dist/README.md

storybook:
	npm run build-storybook
	npm run build-storybook-v3
	mkdir -p public
	mv storybook-static public/storybook
	mv storybook-static-v3 public/storybook3

deploy: storybook docs
	ssh -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null $(SERVER) mkdir -p "~/rsp"
	scp -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -r documentation/public/* "$(SERVER):~/rsp/."
	scp -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -r public/* "$(SERVER):~/rsp/."

ci-deploy:
	@if [ "$$VERSION" == "major" ] || [ "$$VERSION" == "minor" ] || [ "$$VERSION" == "patch" ] || [ "$$VERSION" == "website only" ]; then \
		$(MAKE) deploy; \
	fi

# Run this as make version VERSION={patch|minor|major}
version:
	lerna version ${VERSION} --yes --no-commit-hooks -m "chore(release): publish"
	cp src/package.json dist/package.json

ci-version:
	if [ "$$VERSION" != "publish only" ]; then \
		$(MAKE) version; \
	fi

publish: build ci-version
	lerna publish from-git --yes --registry $(NPM_REGISTRY) --contents dist

ci-publish:
	@if [ "$$VERSION" != "website only" ]; then \
		$(MAKE) publish; \
	fi

# Run this on Jenkins with VERSION={patch|minor|major} as an argument, this will bump all the changed packages
# So major bumps everything as major, minor bumps everything as minor, ...
ci:
	@if [ ! -z "$$VERSION" ] && [ "$$VERSION" != "noop" ]; then \
		$(MAKE) ci-deploy; \
		$(MAKE) ci-publish; \
	fi
