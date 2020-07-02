#!/bin/bash

# SETUP_URL="https://bit.ly/rmferrer_env_bootstrap"; /bin/bash -c "$(curl -fsSL ${SETUP_URL} || wget ${SETUP_URL} -O - )";

_install_brew() {
	/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"	
}

_uname() {
	echo "$(uname -a | tr '[:upper:]' '[:lower:]')"
}

_pkg_install() {
	UNAME=$(_uname)
	if [[ $UNAME =~ "darwin" || $UNAME =~ "ubuntu" ]]; then
		brew install "${@}" && brew upgrade "${@}"
	elif [[ $UNAME =~  "raspberrypi" ]]; then
		sudo apt-get -y install "${@}"
	fi	
}

_run_or_exit() {
	local local_cmd="${@}"
	eval "${local_cmd}" 
	local local_status="${?}"
	if [[ ${local_status} == 0 ]]; then 
		return 0
	else
		printf "Failed running: ${local_cmd}\nStatus: ${local_status}\nExiting..."
		exit 1
	fi
}

_install_package_manager() {
	UNAME=$(_uname)

	printf "Attempting to install package manager...\n\n"
	printf "System detected: ${UNAME}\n\n\n"

	if [[ ${UNAME} =~ "darwin" ]]; then
		printf "Setting up macOS...\n\n"
		_install_brew
		brew update
	elif [[ ${UNAME} =~ "ubuntu" ]]; then
		printf "Setting up ubuntu...\n\n"
		sudo apt-get -y install build-essential curl file git
		_install_brew
		eval $(/home/linuxbrew/.linuxbrew/bin/brew shellenv)
		brew update
	elif [[ ${UNAME} =~  "raspberrypi" ]]; then
		printf "Setting up Raspberry Pi...\n\n"
		sudo apt-get -y update
	else 
		printf "System not recognized! uname -a: ${UNAME}\n\n"
		return 1
	fi
}

_install_test_packages() {
	_run_or_exit _pkg_install hello
}

_install_base_packages() {
	_run_or_exit _pkg_install git zsh
	UNAME=$(_uname)
	if [[ ${UNAME} =~ "darwin" ]]; then
		_run_or_exit brew cask install 1password-cli
	else
		printf "Please install one password and then type any key.\n\n"
		printf "https://app-updates.agilebits.com/product_history/CLI\n\n\n"
		read DUMMY
	fi
	# verify 1p
	_run_or_exit op help > /dev/null
}

_1p_logged_in() {
	op list templates > /dev/null 2>&1
}


_1p_login() {
	readonly max_retries=3
	[[ -f ${HOME}/.op/config ]] && rm ${HOME}/.op/config

	local retries=0
	while ! _1p_logged_in && [[ ${retries} < ${max_retries} ]]; do
		printf "Enter 1password domain: "
		read domain
		printf "Enter 1password email: "
		read email
		printf "Enter shorthand: "
		read shorthand
	
		retries=$((retries + 1))
		if [[ $shorthand ]]; then 
		    eval $(op signin ${domain} ${email} --shorthand ${shorthand});
		else
		    eval $(op signin ${domain} ${email});
		fi
	done

	_1p_logged_in
}

_install_chezmoi() {
	UNAME=$(_uname)
	if [[ ${UNAME} =~ "darwin" || ${UNAME} =~ "ubuntu" ]]; then
		_pkg_install chezmoi
	elif [[ ${UNAME} =~  "raspberrypi" ]]; then
		sudo apt-get -y install golang && sudo apt-get -y upgrade golang && \
			go get -u github.com/twpayne/chezmoi
	fi	
}

_manage_dotfiles() {
	CHEZMOI_DIR="${HOME}/.local/share/chezmoi"

	if [[ -d "${CHEZMOI_DIR}" ]]; then
		printf "Chezmoi dir exists. Delete it? [y/n]: "
		read DELETE_CHEZMOI_DIR
		if [[ ${DELETE_CHEZMOI_DIR} = 'y' ]]; then
			rm -rf "${CHEZMOI_DIR}"
		fi
	fi

	_run_or_exit _install_chezmoi

	printf "Logging into 1password...\n\n"

	_run_or_exit _1p_login
	
	printf "Logged in successfully!\n\n"

	printf "Enter OP Key Id: "

	read KEY_ID

	printf "Enter dotfiles repo uri: "
	
	read DOTFILES_URI

	ssh-agent bash -c "
		ssh-add -D
		ssh-add - <<< \"$(op get document ${KEY_ID})\" 
		chezmoi init \"${DOTFILES_URI}\" --apply;
		op signout;
		"

	${SHELL}
}

_main() {
	_install_package_manager

	_install_test_packages

	_install_base_packages

	_manage_dotfiles
}

_main