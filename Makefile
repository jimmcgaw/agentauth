build:
	docker compose -f deploy/docker-compose.yml build


start:
	docker compose -f deploy/docker-compose.yml up