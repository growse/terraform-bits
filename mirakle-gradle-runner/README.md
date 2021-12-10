# Mirakle Android Gradle builds on EC2

For compute-heavy compilations of Android / Gradle projects, [Mirakle](https://github.com/Adambl4/mirakle) allows the execution of the build to be carried out on an SSH-reachable remote runner. Essentially SCP'ing the contents of the project to the remote endpoint and then actually calling gradle on the remote host before re-syncing the project directory back locally.

So here's some terraform that can spin up and provision an EC2 spot instance in a dedicated VPC and spits out the public DNS name.

`mirakle_init.gradle` contains the gradle configuration used to configure the mirakle plugin. Enable this by `ln -s $(pwd)/mirakle_init.gradle ~/.gradle/init.d/mirakle_init.gradle`. By default all gradle builds will be offloaded unless `-x mirakle` is passed.

Some SSH configuration is needed to set up an endpoint alias called `mirakle`:

```
Host mirakle
        User admin
        Hostname <Public DNS name of EC2 instance>
        Port 22
        IdentityFile ~/.ssh/id_ed25519
        PreferredAuthentications publickey
        ControlMaster auto
        ControlPath /tmp/%r@%h:%p
        ControlPersist 1h
        StrictHostKeyChecking no
```
