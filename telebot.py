#!/usr/bin/env python3
import sys
import subprocess
import os
import glob
import asyncio
import logging
import time
import argparse
import json
from typing import List, Optional, Union, Dict, Any
from dataclasses import dataclass, field, asdict
from pathlib import Path

@dataclass
class BotConfig:
    """Configuration for the Telegram bot"""
    api_id: str
    api_hash: str
    bot_token: str
    chat_id: int
    message: str
    topic_id: Optional[int] = None
    files_path: Optional[str] = None
    max_files_per_group: int = 10
    retry_attempts: int = 3
    retry_delay: int = 5
    config_file: Optional[str] = None
    dry_run: bool = False
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'BotConfig':
        """Create a BotConfig instance from a dictionary"""
        # Filter out any keys not in the dataclass
        valid_fields = {f.name for f in fields(cls)}
        filtered_data = {k: v for k, v in data.items() if k in valid_fields}
        return cls(**filtered_data)
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for saving to config file"""
        return asdict(self)


class ColoredFormatter(logging.Formatter):
    """Custom formatter for colorful console output"""
    
    COLORS = {
        'DEBUG': '\033[94m',  # Blue
        'INFO': '\033[92m',   # Green
        'WARNING': '\033[93m',  # Yellow
        'ERROR': '\033[91m',   # Red
        'CRITICAL': '\033[91m\033[1m',  # Bold Red
        'RESET': '\033[0m'
    }
    
    def format(self, record):
        log_message = super().format(record)
        if record.levelname in self.COLORS:
            return f"{self.COLORS[record.levelname]}{log_message}{self.COLORS['RESET']}"
        return log_message


class DependencyManager:
    """Manages script dependencies"""
    REQUIRED_PACKAGES = ['telethon', 'colorama']
    
    @staticmethod
    def install_package(package: str) -> bool:
        """Install a Python package using pip"""
        try:
            logging.info(f"Installing {package}...")
            subprocess.check_call(
                [sys.executable, "-m", "pip", "install", package],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )
            logging.info(f"Successfully installed {package}")
            return True
        except subprocess.CalledProcessError as e:
            logging.error(f"Failed to install {package}: {str(e)}")
            return False

    @classmethod
    def check_and_install_dependencies(cls) -> None:
        """Check for and install required dependencies"""
        installed = []
        failed = []

        for package in cls.REQUIRED_PACKAGES:
            try:
                __import__(package)
                installed.append(package)
                logging.debug(f"{package} is already installed")
            except ImportError:
                if cls.install_package(package):
                    installed.append(package)
                else:
                    failed.append(package)

        if failed:
            logging.error(f"Failed to install required packages: {', '.join(failed)}")
            sys.exit(1)
        elif set(installed) != set(cls.REQUIRED_PACKAGES):
            logging.info("All dependencies installed. Restarting script...")
            os.execv(sys.executable, ['python3'] + sys.argv)
        else:
            logging.info("All dependencies are properly installed!")


class TelegramBot:
    """Telegram bot handler for sending messages and files"""
    
    def __init__(self, config: BotConfig):
        """Initialize the bot with configuration"""
        self.config = config
        
        # Import here after dependency check
        from telethon import TelegramClient
        from colorama import init
        init(autoreset=True)
        
        self.client = TelegramClient('bot_session', config.api_id, config.api_hash)
        
    async def start(self) -> None:
        """Start the bot client"""
        await self.client.start(bot_token=self.config.bot_token)
        me = await self.client.get_me()
        logging.info(f"Bot is active! Logged in as @{me.username}")

    async def stop(self) -> None:
        """Stop the bot client"""
        await self.client.disconnect()
        logging.info("Bot has been deactivated")

    async def send_message(self, message: str, retry: bool = True) -> None:
        """Send a message to the specified chat"""
        if self.config.dry_run:
            logging.info(f"DRY RUN: Would send message to chat ID {self.config.chat_id}: {message[:50]}...")
            return
            
        attempts = self.config.retry_attempts if retry else 1
        
        for attempt in range(1, attempts + 1):
            try:
                kwargs = {
                    'entity': self.config.chat_id,
                    'parse_mode': 'HTML',
                    'message': message
                }
                if self.config.topic_id:
                    kwargs['reply_to'] = self.config.topic_id
                
                await self.client.send_message(**kwargs)
                logging.info(f"Message sent successfully to chat ID: {self.config.chat_id}")
                return
            except Exception as e:
                if attempt < attempts:
                    logging.warning(f"Attempt {attempt} failed: {str(e)}. Retrying in {self.config.retry_delay} seconds...")
                    await asyncio.sleep(self.config.retry_delay)
                else:
                    logging.error(f"Failed to send message after {attempts} attempts: {str(e)}")
                    raise

    async def send_files(self, files: List[Path], message: str, retry: bool = True) -> None:
        """Send files with a message to the specified chat"""
        if not files:
            logging.warning("No files to send")
            return
            
        if self.config.dry_run:
            file_names = [f.name for f in files]
            logging.info(f"DRY RUN: Would send {len(files)} files to chat ID {self.config.chat_id}")
            logging.info(f"Files: {', '.join(file_names[:5])}" + ("..." if len(file_names) > 5 else ""))
            return
            
        file_groups = [files[i:i + self.config.max_files_per_group] 
                      for i in range(0, len(files), self.config.max_files_per_group)]
        
        total_groups = len(file_groups)
        logging.info(f"Sending {len(files)} files in {total_groups} groups")
        
        for group_idx, file_group in enumerate(file_groups, 1):
            group_message = f"{message}\n\n(Group {group_idx}/{total_groups})"
            attempts = self.config.retry_attempts if retry else 1
            
            for attempt in range(1, attempts + 1):
                try:
                    kwargs = {
                        'entity': self.config.chat_id,
                        'file': [str(f) for f in file_group],
                        'parse_mode': 'HTML',
                        'caption': group_message
                    }
                    if self.config.topic_id:
                        kwargs['reply_to'] = self.config.topic_id
                    
                    await self.client.send_file(**kwargs)
                    logging.info(f"File group {group_idx}/{total_groups} sent successfully")
                    # Add a small delay between groups to avoid rate limiting
                    if group_idx < total_groups:
                        await asyncio.sleep(1)
                    break
                except Exception as e:
                    if attempt < attempts:
                        logging.warning(f"Attempt {attempt} for group {group_idx} failed: {str(e)}. Retrying in {self.config.retry_delay} seconds...")
                        await asyncio.sleep(self.config.retry_delay)
                    else:
                        logging.error(f"Failed to send file group {group_idx} after {attempts} attempts: {str(e)}")
                        raise


def setup_logging(verbose: bool = False) -> None:
    """Configure logging with colored output"""
    log_level = logging.DEBUG if verbose else logging.INFO
    
    # Configure root logger
    root_logger = logging.getLogger()
    root_logger.setLevel(log_level)
    
    # Clear existing handlers
    for handler in root_logger.handlers[:]:
        root_logger.removeHandler(handler)
    
    # Console handler with colors
    console_handler = logging.StreamHandler()
    console_handler.setFormatter(ColoredFormatter('%(asctime)s - %(levelname)s - %(message)s'))
    root_logger.addHandler(console_handler)
    
    # File handler
    file_handler = logging.FileHandler('bot.log')
    file_handler.setFormatter(logging.Formatter('%(asctime)s - %(levelname)s - %(message)s'))
    root_logger.addHandler(file_handler)


def load_config_file(config_path: str) -> Dict[str, Any]:
    """Load configuration from a JSON file"""
    try:
        with open(config_path, 'r') as f:
            return json.load(f)
    except Exception as e:
        logging.error(f"Failed to load config file: {str(e)}")
        sys.exit(1)


def save_config_file(config: BotConfig, config_path: str) -> None:
    """Save configuration to a JSON file"""
    try:
        with open(config_path, 'w') as f:
            json.dump(config.to_dict(), f, indent=2)
        logging.info(f"Configuration saved to {config_path}")
    except Exception as e:
        logging.error(f"Failed to save config file: {str(e)}")


def parse_arguments() -> BotConfig:
    """Parse command line arguments"""
    parser = argparse.ArgumentParser(description="Telegram Bot for sending messages and files")
    
    # Config file
    parser.add_argument('--config', '-c', help='Path to config file (JSON)')
    parser.add_argument('--save-config', help='Save configuration to specified file')
    
    # Required args (unless config file is provided)
    parser.add_argument('--api-id', help='Telegram API ID')
    parser.add_argument('--api-hash', help='Telegram API Hash')
    parser.add_argument('--bot-token', help='Telegram Bot Token')
    parser.add_argument('--chat-id', type=int, help='Chat ID to send messages to')
    parser.add_argument('--message', '-m', help='Message text to send')
    
    # Optional args
    parser.add_argument('--topic-id', type=int, help='Topic ID for forum channels')
    parser.add_argument('--files', help='Path or glob pattern for files to send')
    parser.add_argument('--max-files', type=int, default=10, help='Maximum files per message group')
    parser.add_argument('--retry', type=int, default=3, help='Number of retry attempts')
    parser.add_argument('--retry-delay', type=int, default=5, help='Seconds to wait between retries')
    parser.add_argument('--dry-run', action='store_true', help='Run without sending actual messages')
    parser.add_argument('--verbose', '-v', action='store_true', help='Enable verbose logging')
    
    # Legacy positional arguments support (for backward compatibility)
    parser.add_argument('legacy_args', nargs='*', help=argparse.SUPPRESS)
    
    args = parser.parse_args()
    
    # Set up logging early
    setup_logging(args.verbose)
    
    # Handle legacy positional arguments for backward compatibility
    if args.legacy_args and len(args.legacy_args) >= 5:
        logging.warning("Using legacy positional arguments. Consider switching to named arguments.")
        legacy_config = BotConfig(
            api_id=args.legacy_args[0],
            api_hash=args.legacy_args[1],
            bot_token=args.legacy_args[2],
            message=args.legacy_args[3],
            chat_id=int(args.legacy_args[4])
        )
        
        if len(args.legacy_args) > 5:
            try:
                legacy_config.topic_id = int(args.legacy_args[5])
                if len(args.legacy_args) > 6:
                    legacy_config.files_path = args.legacy_args[6]
            except ValueError:
                legacy_config.files_path = args.legacy_args[5]
                
        return legacy_config
    
    # Load from config file if provided
    config_data = {}
    if args.config:
        config_data = load_config_file(args.config)
    
    # Override with command line arguments
    for key, value in vars(args).items():
        if key in ['legacy_args', 'config', 'save_config', 'verbose']:
            continue
        if value is not None:
            if key == 'files':
                config_data['files_path'] = value
            elif key == 'max_files':
                config_data['max_files_per_group'] = value
            else:
                config_data[key] = value
    
    # Validate required fields
    required_fields = ['api_id', 'api_hash', 'bot_token', 'chat_id', 'message']
    missing_fields = [field for field in required_fields if field not in config_data or not config_data[field]]
    
    if missing_fields:
        logging.error(f"Missing required configuration: {', '.join(missing_fields)}")
        parser.print_help()
        sys.exit(1)
    
    # Create config object
    config = BotConfig.from_dict(config_data)
    
    # Save config if requested
    if args.save_config:
        save_config_file(config, args.save_config)
    
    return config


async def main():
    """Main function to run the bot"""
    try:
        config = parse_arguments()
        DependencyManager.check_and_install_dependencies()
        
        bot = TelegramBot(config)
        
        await bot.start()
        
        start_time = time.time()
        
        if config.files_path:
            files = list(Path().glob(config.files_path))
            if files:
                await bot.send_files(files, config.message)
            else:
                logging.warning(f"No files found matching pattern: {config.files_path}")
                await bot.send_message(config.message)
        else:
            await bot.send_message(config.message)
        
        elapsed_time = time.time() - start_time
        logging.info(f"Operation completed in {elapsed_time:.2f} seconds")
    
    except KeyboardInterrupt:
        logging.info("Operation cancelled by user")
        return 1
    except Exception as e:
        logging.error(f"Error during execution: {str(e)}", exc_info=True)
        return 1
    finally:
        if 'bot' in locals():
            await bot.stop()
    
    return 0


if __name__ == '__main__':
    from dataclasses import fields
    exit_code = asyncio.run(main())
    sys.exit(exit_code)