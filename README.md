# My Update Notifier

This is a personal project for the purpose of practicing programming and to ease my own inconvenience in the form of checking various sites and forums. The aim is to build an app that will gather updates and push notifications to clients.

## Overview

The application consists of two main components:
1. Backend - Built using Django, hosted on a VPS.
2. Android Client - Developed using Kotlin and Jetpack Compose.

---

## Backend

The backend has the following apps:
1. `accounts` - Manages user account creation, login, and authentication.
2. `url_monitoring` - Handles URL storage, CRUD operations, update checks, and push notifications.

### accounts

- Handles user account creation and login.

### url_monitoring

- Stores URLs with associated metadata
- Manages CRUD operations for URLs
- Checks for updates based on URL categories
- Stores updates for URLs
- Sends push notifications for updates

---

## Android Client

The Android client is built using Kotlin with Jetpack Compose and interacts with the Django backend through API calls.

Key features:
1. User account creation and login
2. User site/URL management (CRUD)
3. Fetches and displays a list of updates

---

## Getting Started

### Prerequisites

- Python 3.x
- Android Studio

### Installation and Setup

1. Clone the repository.
    ```
    git clone https://github.com/your_username/my-update-notifier.git
    cd backend
    ```
2. Activate venv
    ```
    source venv/bin/activate
    ```
3. Install the required Python packages for the backend.
    ```
    pip install -r requirements.txt
    ```
4. Apply the Django migrations.
    ```
    python manage.py migrate
    ```
5. Run the Django development server.
    ```
    python manage.py runserver
    ```

---

## TODOs
* Create Django app
  * Create accounts app
    * Test it
  * Create URL monitoring app
    * Create app
    * Add logic for one site
      * Test it
    * Repeat for other sites
    * Create push notification functionality
      * Test it   
* Create Android client
    * Create log in portion
      * Create tests
    * Create user account management UI (CRUD ops)
    * Create notifications receiver
      * Test it
    * Create updates list view
* Create full end to end tests if not hard
* Create docker image for server
* Figure out deployment
