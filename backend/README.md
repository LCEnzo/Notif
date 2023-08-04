
## How to Login and Register an account

### User Registration:
  - Route: `api/v1/accounts/users/`
  - Method: `POST`
  - Body: 
    ```json
    {
		"username": "new_user",
		"email": "newuser@example.com",
		"password": "securepassword123 securepassword123"
	}
    ```
	> Note: name is an optional field, so is the password. 


### User Login:
  - Route: `api/v1/token/`
  - Method: `POST`
  - Body: 
    ```json
    {
        "username": "new_user",
        "password": "securepassword123 securepassword123"
    }
    ```
  
## TODOs:
 - Deal with CORS
