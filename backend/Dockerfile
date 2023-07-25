FROM python:3.11.4-slim

# prevents Python from writing out pyc files 
ENV PYTHONDONTWRITEBYTECODE 1 
# forces the stdout and stderr streams to be unbuffered, used for logging
ENV PYTHONUNBUFFERED 1

WORKDIR /backend

# Assumes that the backend folder is in the same directory as the Dockerfile
COPY . .

WORKDIR /backend

RUN apt update && apt -y upgrade
RUN pip install --upgrade pip setuptools wheel

RUN pip install --no-cache-dir -r requirements.txt

# In use for SQLite
RUN python manage.py migrate

EXPOSE 8000

# CMD ["python", "manage.py", "runserver", "0.0.0.0:8000"]
CMD  ["bash"]
