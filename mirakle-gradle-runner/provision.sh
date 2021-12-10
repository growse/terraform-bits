#! /bin/bash
# Hack to set the ANDROID_SDK_ROOT env var to mirakle clients
echo PermitUserEnvironment yes >> /etc/ssh/sshd_config
sudo -u admin sh -c "echo ANDROID_SDK_ROOT=/home/admin/sdk > /home/admin/.ssh/environment"
sudo systemctl restart ssh
sudo apt-get update
sudo apt-get install -y rsync openjdk-11-jdk htop unzip
# Bootstrap the Android SDK cmdline tools
mkdir -p /home/admin/cmdline-tools-bootstrap
curl -L -o /home/admin/commandlinetools.zip https://dl.google.com/android/repository/commandlinetools-linux-7583922_latest.zip
unzip /home/admin/commandlinetools.zip -d /home/admin/cmdline-tools-bootstrap
# Install the actual SDK
sudo -u admin sh -c "echo 'y' | /home/admin/cmdline-tools-bootstrap/cmdline-tools/bin/sdkmanager  --sdk_root=/home/admin/sdk \"cmdline-tools;latest\""
sudo -u admin /home/admin/sdk/cmdline-tools/latest/bin/sdkmanager "platforms;android-30" "platform-tools" "build-tools;30.0.2"