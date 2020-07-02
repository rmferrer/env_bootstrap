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
		brew install "${@}"
	elif [[ $UNAME =~  "raspberrypi" ]]; then
		sudo apt-get -y install "${@}"
	fi	
}

_run_or_exit() {
	readonly local_cmd="${@}"
	eval "${local_cmd}" 
	readonly local_status="${?}"
	if [[ ${local_status} == 0 ]]; then 
		return 0
	else
		echo "Failed running: ${local_cmd}\nStatus: ${local_status}\nExiting..."
		exit 1
	fi
}

_install_package_manager() {
	UNAME=$(_uname)

	echo "Attempting to install package manager...\n\n"
	echo "System detected: ${UNAME}"

	if [[ ${UNAME} =~ "darwin" ]]; then
		echo "Setting up macOS..."
		_install_brew
		brew update
	elif [[ ${UNAME} =~ "ubuntu" ]]; then
		echo "Setting up ubuntu..."
		sudo apt-get -y install build-essential curl file git
		_install_brew
		eval $(/home/linuxbrew/.linuxbrew/bin/brew shellenv)
		brew update
	elif [[ ${UNAME} =~  "raspberrypi" ]]; then
		echo "Setting up Raspberry Pi..."
		sudo apt-get -y update
	else 
		echo "System not recognized! uname -a: ${UNAME}"
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
		echo "Please install one password and then type any key."
		echo "https://app-updates.agilebits.com/product_history/CLI"
		read DUMMY
	fi
	# verify 1p
	_run_or_exit op help > /dev/null
}

_1p_logged_in() {
	op list templates > /dev/null 2>&1
}

_1p_login() {
  local max_retries=2
  while getopts ":r:a:e:k" opt; do
    case ${opt} in
      r ) max_retries=${OPTARG}
        ;;
      a ) local domain=${OPTARG}
        ;;
      e ) local email=${OPTARG}
        ;;
      k ) 
		echo "Enter 1password domain"
		read domain
		echo "Enter 1password email"
		read email
        ;;
      \?) 
		echo "Invalid option -${OPTARG}" >&2
		return 1
        ;;
      : ) 
		echo "Invalid option: ${OPTARG} requires an argument" 1>&2
		return 1
        ;;
    esac
  done
  shift $((OPTIND -1))


  local retries=0
  while ! _1p_logged_in && [[ ${retries} < ${max_retries} ]]; do
    retries=$((retries + 1))
    eval $(op signin ${domain} ${email});
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
		echo "Chezmoi dir exists. Delete it? [y/n]"
		read DELETE_CHEZMOI_DIR
		if [[ ${DELETE_CHEZMOI_DIR} = 'y' ]]; then
			rm -rf "${CHEZMOI_DIR}"
		fi
	fi

	_run_or_exit _install_chezmoi

	echo "Logging into 1password...\n\n"

	_run_or_exit _1p_login -k
	
	echo "Logged in successfully!\n\n"

	echo "Enter Key Id: "

	read KEY_ID
	_run_or_exit ssh-add - <<< "$(op get document ${KEY_ID})"

	echo "Enter dotfiles repo uri: "
	
	read DOTFILES_URI
	
	chezmoi init "${DOTFILES_URI}" --apply
	
	${SHELL}
	op signout
}

_main() {
	_install_package_manager

	_install_test_packages

	_install_base_packages

	_manage_dotfiles
}

_main