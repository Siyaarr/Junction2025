from twilio.rest import Client
from dotenv import load_dotenv
import os

# Load environment variables from .env file
load_dotenv()

def setup_twilio_webhook():
    # Get credentials from environment
    account_sid = os.getenv('TWILIO_ACCOUNT_SID')
    auth_token = os.getenv('TWILIO_AUTH_TOKEN')
    phone_number = os.getenv('TWILIO_PHONE_NUMBER')
    domain = os.getenv('DOMAIN')
    
    try:
        # Initialize Twilio client
        client = Client(account_sid, auth_token)
        
        # Find and update phone number
        phone_numbers = client.incoming_phone_numbers.list(phone_number=phone_number)
        
        if phone_numbers:
            phone = phone_numbers[0]
            webhook_url = f"https://{domain}/voice"
            
            phone.update(
                voice_url=webhook_url,
                voice_method='POST'
            )
            
            print(f"✅ Successfully configured {phone_number}")
            print(f"   Voice webhook: {webhook_url}")
            return True
            
        else:
            print(f"❌ Phone number {phone_number} not found in your account")
            return False
            
    except Exception as e:
        print(f"❌ Error configuring webhook: {e}")
        return False

if __name__ == "__main__":
    setup_twilio_webhook()
