# Don't knock yourself out! Production ready debian packages are available.

## Install SigScale package repository configuration:

### Debian 12 (bookworm)
	curl -sLO https://asia-east1-apt.pkg.dev/projects/sigscale-release/pool/debian-bookworm/sigscale-release_1.4.5-1+debian12_all_dc4f6c6b7f70b2853c71dac983dc4008.deb
	sudo dpkg -i sigscale-release_*.deb
	sudo apt update

## Install SigScale OCS Bench:
	sudo apt install sigscale-ocs-bench
	sudo systemctl enable ocs_bench
	sudo systemctl start ocs_bench
	sudo systemctl status ocs_bench

## Support
Contact <support@sigscale.com> for further assistance.

