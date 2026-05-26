FROM elitemind/wzmlxdz:main

WORKDIR /usr/src/app

COPY requirements.txt .
RUN uv pip install --no-cache-dir -r requirements.txt

COPY . .

RUN chmod -R 777 /usr/src/app

CMD ["bash", "start.sh"]
