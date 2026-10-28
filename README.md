# Print Room HQ for Docker and Home Assistant

[Print Room HQ](https://printroomhq.com) is the print room dashboard for Bambu Lab, Snapmaker U1 and Klipper printers: live printers and cameras, AI failure watching, a print queue, your model library, spools, costs and quotes.

This repo holds the Docker image and the Home Assistant add-on. Setup guide: **https://printroomhq.com/guide/docker/**

## Docker

```sh
curl -fsSLO https://raw.githubusercontent.com/brianmayes/printroomhq-docker/main/docker-compose.yml
docker compose up -d
```

Then open `http://<this computer>:8080`. Or with plain Docker:

```sh
docker run -d --name printroomhq --restart unless-stopped --network host \
  -v printroomhq:/printroomhq -e TZ=America/New_York ghcr.io/brianmayes/printroomhq:latest
```

The image is a small starter (amd64 and arm64). On first start it downloads the latest Print Room HQ from printroomhq.com, and it updates itself the same way the Raspberry Pi version does. Your printers, settings and history live in the `printroomhq` volume.

## Home Assistant

[![Add this repository to your Home Assistant](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2Fbrianmayes%2Fprintroomhq-docker)

Or in Home Assistant: Settings › Add-ons › Add-on Store › ⋮ › Repositories, add `https://github.com/brianmayes/printroomhq-docker`, then install **Print Room HQ**.

## License

Print Room HQ is free for personal, noncommercial use. Using it for a business? See [commercial licenses](https://printroomhq.com/#shop).
