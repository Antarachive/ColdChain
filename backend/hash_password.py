"""Usage: python backend/hash_password.py <password>   -> prints a hash to store in SystemUser.PasswordHash"""
import sys
from werkzeug.security import generate_password_hash

print(generate_password_hash(sys.argv[1], method="pbkdf2:sha256"))
