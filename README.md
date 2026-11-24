# Space Engineers Dedicated Debian Docker Container

First of all thanks to [7thCore](https://github.com/7thCore) and [mmmaxwwwell](https://github.com/mmmaxwwwell) for their great prework making a linux dedicated server for Space Engineers real!

I took parts of their projects to create this one (see credits)

## Why?

I wanted to have a more cleaner docker container with less dependencies (integrate sesrv-script parts instead of wget the whole script) and a little more configuration through composer files.

## KeyFacts

| Key         | :latest              | :winestaging         |
| ----------- | -------------------- | -------------------- |
| OS          | Debian 13 (Trixie)   | Debian 13 (Trixie)   |
| Wine        | 9.0~trixie-1         | 9.20~trixie-1        |
| Docker size | ~1.82GB compressed   | ~1.82GB compressed   |
| Build Time  | ~ 19 Minutes         | ~ 19 Minutes         |

`:winestaging` can be built from this Dockerfile with
`--build-arg WINEBRANCH=staging --build-arg WINEVERSION=9.20~trixie-1`.

## How to use

First you have to use the `Space Engineers Dedicated Server` Tool to setup your world.

(detailed instructions follow when requested)

After you have saved your world upload it (the instance directory) to your docker host machine `/appdata/space-engineers/instances/`.

## Using docker-compose with precompiled docker image (devidian/spaceengineers)

Create a [docker-compose.yml](docker-compose.yml) (see example below) and execute `docker-compose up -d`

Do not forget to rename `TestInstance` with your instance name!

### example composer - just copy and adjust

```yaml
services:
  se-server:
    image: devidian/spaceengineers:winestaging
    container_name: se-ds-docker
    restart: unless-stopped
    volumes:
      # left side: your docker-host machine
      # right side: the paths in the image (!!do not change!!)
      - /appdata/space-engineers/plugins:/appdata/space-engineers/plugins
      - /appdata/space-engineers/instances:/appdata/space-engineers/instances
      - /appdata/space-engineers/SpaceEngineersDedicated:/appdata/space-engineers/SpaceEngineersDedicated
      - /appdata/space-engineers/steamcmd:/root/.steam
    ports:
      - target: 27016
        published: 27016
        protocol: udp
        mode: host
    environment:
      - WINEDEBUG=-all
      - INSTANCE_NAME=TestInstance
      - PUBLIC_IP=1.2.3.4
      # public ip required for healthcheck
```

## Build the image yourself from source

Download this repository and run `docker-compose up -d`

## Use the docker image as source for your own image

If you want to extend the image create a `Dockerfile` and use `FROM devidian/spaceengineers:latest`

## FAQ

### Can i use plugins?

Yes just copy plugins to `/appdata/space-engineers/plugins` and they will be added or removed by the [entrypoint.sh](entrypoint.sh) script

### Can i run mods?

Yes. On every start [entrypoint.sh](entrypoint.sh) scans
`SpaceEngineers-Dedicated.cfg` and the world saves for workshop IDs and
downloads/updates them with the Linux `steamcmd` before the server starts.
It also replaces the outdated Steamworks DLLs shipped with the dedicated
server; without that the Steam client under Wine fails with
`Staging/Install library folder not found` when it tries to download a mod.

### Can i contribute?

Sure, feel free to submit merge requests or issues if you have anything to improve this project. If you just have a question, use Github Discussions.

## Credits

| User                                                      | repo / fork                                                            | what (s)he did for this project |
| --------------------------------------------------------- | ---------------------------------------------------------------------- | ------------------------------- |
| [mmmaxwwwell](https://github.com/mmmaxwwwell)             | https://github.com/mmmaxwwwell/space-engineers-dedicated-docker-linux  | downgrading for dotnet48        |
| [7thCore](https://github.com/7thCore)                     | https://github.com/7thCore/sesrv-script                                | installer bash script           |
| [Diego Lucas Jimenez](https://github.com/tanisdlj)        | -                                                                      | Improved Dockerfile             |
| [EthicalObligation](https://github.com/EthicalObligation) | https://github.com/EthicalObligation/docker-spaceengineers-healthcheck | Healthcheck & Quicker startup   |
| [draconb](https://github.com/draconb)                     | -                                                                      | Hints for plugin support        |

## Known issues

- **Workshop mod download failures**
  - The image refreshes `steamclient64.dll`, `tier0_s64.dll` and
    `vstdlib_s64.dll` from the app root on every start and pre-downloads the
    configured mods with the Linux `steamcmd`. If a mod still fails, stop the
    server, delete `content/244850/<mod-id>` and
    `appworkshop_244850.acf` from
    `/appdata/space-engineers/instances/<INSTANCE_NAME>`, and start it again.
- **VRage Remote Client**
  - I personally could not manage to connect with te remote client, if anyone gets a connection please tell me (and maybe how you fixed it) [see here](https://github.com/Devidian/docker-spaceengineers/issues/36)
