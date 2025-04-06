# Don't knock yourself out! Production ready debian packages are available.

## Install SigScale package repository configuration:

### Ubuntu 24.04 LTS (noble)
	curl -sLO https://asia-east1-apt.pkg.dev/projects/sigscale-release/pool/ubuntu-noble/sigscale-release_1.4.5-1+ubuntu24.04_all_dccb359ae044de02cad8f728fb007658.deb
	sudo dpkg -i sigscale-release_*.deb
	sudo apt update

## Install SigScale OCS Bench:
	sudo apt install sigscale-ocs-bench
	sudo systemctl enable sigscale-ocs-bench
	sudo systemctl start sigscale-ocs-bench
	sudo systemctl status sigscale-ocs-bench

## Support
Contact <support@sigscale.com> for further assistance.

