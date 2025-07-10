#!/bin/bash

# 🤖 Docker Agent Templates Generator - Cryonith LLC
# Creates additional AI agent containers for the microservices architecture

set -euo pipefail

WORK_DIR="/home/operator/core"
NODE_ID=$(cat "$WORK_DIR/system_info.json" | jq -r '.node_id' 2>/dev/null || echo "unknown")

echo "🤖 Creating AI Agent Templates for Node: $NODE_ID"

# Create trading agent
echo "📈 Creating Trading Agent..."
mkdir -p "$WORK_DIR/docker/trading-agent"

cat > "$WORK_DIR/docker/trading-agent/Dockerfile" << 'EOF'
FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

CMD ["python", "trading_agent.py"]
EOF

cat > "$WORK_DIR/docker/trading-agent/requirements.txt" << 'EOF'
fastapi==0.104.1
aiohttp==3.9.1
numpy==1.24.3
pandas==2.0.3
scikit-learn==1.3.0
asyncio-mqtt==0.13.0
redis==5.0.1
websockets==12.0
pydantic==2.5.0
python-dateutil==2.8.2
requests==2.31.0
alpaca-trade-api==3.0.0
yfinance==0.2.18
EOF

cat > "$WORK_DIR/docker/trading-agent/trading_agent.py" << 'EOF'
import os
import asyncio
import aiohttp
import json
import logging
from datetime import datetime, timedelta
import pandas as pd
import numpy as np
from typing import Dict, Any, List
import redis.asyncio as redis

NODE_ID = os.getenv("NODE_ID", "unknown")
AGENT_TYPE = os.getenv("AGENT_TYPE", "trading")
ORCHESTRATOR_URL = os.getenv("ORCHESTRATOR_URL", "http://localhost:8001")

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/app/logs/trading-agent.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(f"trading-agent-{NODE_ID}")

class TradingAgent:
    def __init__(self):
        self.agent_id = f"trading-{NODE_ID}-{datetime.now().strftime('%H%M%S')}"
        self.status = "idle"
        self.session = None
        self.cache_client = None
        
    async def initialize(self):
        """Initialize the trading agent"""
        logger.info(f"Initializing trading agent: {self.agent_id}")
        
        self.session = aiohttp.ClientSession()
        
        # Connect to Redis for caching
        try:
            redis_url = os.getenv("REDIS_URL", "redis://host.docker.internal:6379")
            self.cache_client = redis.from_url(redis_url, decode_responses=True)
            await self.cache_client.ping()
            logger.info("Connected to Redis cache")
        except Exception as e:
            logger.error(f"Redis connection failed: {e}")
        
        # Register with orchestrator
        await self.register_with_orchestrator()
        
    async def register_with_orchestrator(self):
        """Register this agent with the orchestrator"""
        try:
            registration_data = {
                "agent_id": self.agent_id,
                "agent_type": AGENT_TYPE,
                "capabilities": [
                    "signal_generation",
                    "risk_analysis",
                    "market_data_processing",
                    "portfolio_optimization"
                ],
                "status": self.status
            }
            
            async with self.session.post(
                f"{ORCHESTRATOR_URL}/register",
                json=registration_data
            ) as response:
                if response.status == 200:
                    logger.info("Successfully registered with orchestrator")
                else:
                    logger.error(f"Failed to register: {response.status}")
                    
        except Exception as e:
            logger.error(f"Error registering with orchestrator: {e}")
    
    async def generate_trading_signal(self, symbol: str, timeframe: str = "1d") -> Dict[str, Any]:
        """Generate trading signal for a given symbol"""
        try:
            logger.info(f"Generating trading signal for {symbol}")
            
            # Simulate market data analysis
            # In production, this would connect to real market data APIs
            price_data = await self.get_market_data(symbol, timeframe)
            
            # Simple moving average strategy (replace with your actual logic)
            signal = self.analyze_price_data(price_data)
            
            # Cache the signal
            if self.cache_client:
                await self.cache_client.setex(
                    f"signal:{symbol}:{self.agent_id}",
                    3600,
                    json.dumps(signal)
                )
            
            return signal
            
        except Exception as e:
            logger.error(f"Error generating signal for {symbol}: {e}")
            return {"error": str(e)}
    
    async def get_market_data(self, symbol: str, timeframe: str) -> pd.DataFrame:
        """Get market data for analysis"""
        # Simulate market data - replace with real API calls
        dates = pd.date_range(end=datetime.now(), periods=100, freq='D')
        prices = 100 + np.cumsum(np.random.randn(100) * 0.5)
        
        return pd.DataFrame({
            'date': dates,
            'close': prices,
            'volume': np.random.randint(1000, 10000, 100)
        })
    
    def analyze_price_data(self, data: pd.DataFrame) -> Dict[str, Any]:
        """Analyze price data and generate signal"""
        try:
            # Simple moving average crossover strategy
            data['sma_20'] = data['close'].rolling(window=20).mean()
            data['sma_50'] = data['close'].rolling(window=50).mean()
            
            latest = data.iloc[-1]
            previous = data.iloc[-2]
            
            # Generate signal based on moving average crossover
            if latest['sma_20'] > latest['sma_50'] and previous['sma_20'] <= previous['sma_50']:
                action = "BUY"
                confidence = 0.75
            elif latest['sma_20'] < latest['sma_50'] and previous['sma_20'] >= previous['sma_50']:
                action = "SELL"
                confidence = 0.75
            else:
                action = "HOLD"
                confidence = 0.5
            
            return {
                "action": action,
                "confidence": confidence,
                "price": float(latest['close']),
                "timestamp": datetime.now().isoformat(),
                "agent_id": self.agent_id,
                "strategy": "sma_crossover"
            }
            
        except Exception as e:
            logger.error(f"Error analyzing price data: {e}")
            return {
                "action": "HOLD",
                "confidence": 0.0,
                "error": str(e)
            }
    
    async def run(self):
        """Main agent loop"""
        logger.info(f"Starting trading agent main loop: {self.agent_id}")
        
        while True:
            try:
                # Check for tasks from orchestrator
                # In production, this would be event-driven
                await asyncio.sleep(30)
                
                # Send heartbeat
                await self.send_heartbeat()
                
            except Exception as e:
                logger.error(f"Error in main loop: {e}")
                await asyncio.sleep(60)
    
    async def send_heartbeat(self):
        """Send heartbeat to orchestrator"""
        try:
            heartbeat_data = {
                "agent_id": self.agent_id,
                "status": self.status,
                "timestamp": datetime.now().isoformat()
            }
            
            async with self.session.post(
                f"{ORCHESTRATOR_URL}/heartbeat",
                json=heartbeat_data
            ) as response:
                if response.status != 200:
                    logger.warning(f"Heartbeat failed: {response.status}")
                    
        except Exception as e:
            logger.error(f"Error sending heartbeat: {e}")
    
    async def cleanup(self):
        """Cleanup resources"""
        if self.session:
            await self.session.close()
        if self.cache_client:
            await self.cache_client.close()

async def main():
    agent = TradingAgent()
    
    try:
        await agent.initialize()
        await agent.run()
    except KeyboardInterrupt:
        logger.info("Trading agent shutting down...")
    finally:
        await agent.cleanup()

if __name__ == "__main__":
    asyncio.run(main())
EOF

# Create risk management agent
echo "⚠️ Creating Risk Management Agent..."
mkdir -p "$WORK_DIR/docker/risk-agent"

cat > "$WORK_DIR/docker/risk-agent/Dockerfile" << 'EOF'
FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

CMD ["python", "risk_agent.py"]
EOF

cat > "$WORK_DIR/docker/risk-agent/requirements.txt" << 'EOF'
fastapi==0.104.1
aiohttp==3.9.1
numpy==1.24.3
pandas==2.0.3
scipy==1.11.1
redis==5.0.1
pydantic==2.5.0
asyncio-mqtt==0.13.0
VaR==1.0.0
pyfolio==0.9.2
EOF

cat > "$WORK_DIR/docker/risk-agent/risk_agent.py" << 'EOF'
import os
import asyncio
import aiohttp
import json
import logging
from datetime import datetime, timedelta
import pandas as pd
import numpy as np
from typing import Dict, Any, List
import redis.asyncio as redis

NODE_ID = os.getenv("NODE_ID", "unknown")
AGENT_TYPE = os.getenv("AGENT_TYPE", "risk")
ORCHESTRATOR_URL = os.getenv("ORCHESTRATOR_URL", "http://localhost:8001")

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/app/logs/risk-agent.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(f"risk-agent-{NODE_ID}")

class RiskAgent:
    def __init__(self):
        self.agent_id = f"risk-{NODE_ID}-{datetime.now().strftime('%H%M%S')}"
        self.status = "idle"
        self.session = None
        self.cache_client = None
        self.risk_limits = {
            "max_position_size": 10000.0,
            "max_daily_loss": 500.0,
            "max_portfolio_risk": 0.02,
            "max_concentration": 0.1
        }
        
    async def initialize(self):
        """Initialize the risk agent"""
        logger.info(f"Initializing risk agent: {self.agent_id}")
        
        self.session = aiohttp.ClientSession()
        
        try:
            redis_url = os.getenv("REDIS_URL", "redis://host.docker.internal:6379")
            self.cache_client = redis.from_url(redis_url, decode_responses=True)
            await self.cache_client.ping()
            logger.info("Connected to Redis cache")
        except Exception as e:
            logger.error(f"Redis connection failed: {e}")
        
        await self.register_with_orchestrator()
        
    async def register_with_orchestrator(self):
        """Register this agent with the orchestrator"""
        try:
            registration_data = {
                "agent_id": self.agent_id,
                "agent_type": AGENT_TYPE,
                "capabilities": [
                    "position_sizing",
                    "var_calculation",
                    "portfolio_risk_analysis",
                    "limit_monitoring",
                    "stop_loss_management"
                ],
                "status": self.status
            }
            
            async with self.session.post(
                f"{ORCHESTRATOR_URL}/register",
                json=registration_data
            ) as response:
                if response.status == 200:
                    logger.info("Successfully registered with orchestrator")
                else:
                    logger.error(f"Failed to register: {response.status}")
                    
        except Exception as e:
            logger.error(f"Error registering with orchestrator: {e}")
    
    async def assess_trade_risk(self, trade_data: Dict[str, Any]) -> Dict[str, Any]:
        """Assess risk for a proposed trade"""
        try:
            logger.info(f"Assessing risk for trade: {trade_data.get('symbol', 'Unknown')}")
            
            symbol = trade_data.get('symbol')
            quantity = trade_data.get('quantity', 0)
            price = trade_data.get('price', 0)
            action = trade_data.get('action', 'BUY')
            
            # Calculate position value
            position_value = abs(quantity * price)
            
            # Check position size limits
            position_risk = self.check_position_limits(position_value)
            
            # Calculate portfolio impact
            portfolio_risk = await self.calculate_portfolio_impact(symbol, quantity, price)
            
            # Calculate Value at Risk
            var_risk = await self.calculate_var(symbol, quantity)
            
            # Overall risk assessment
            overall_risk = max(position_risk['risk_score'], 
                             portfolio_risk['risk_score'],
                             var_risk['risk_score'])
            
            risk_assessment = {
                "trade_approved": overall_risk < 0.7,
                "risk_score": overall_risk,
                "position_risk": position_risk,
                "portfolio_risk": portfolio_risk,
                "var_risk": var_risk,
                "timestamp": datetime.now().isoformat(),
                "agent_id": self.agent_id
            }
            
            # Cache the assessment
            if self.cache_client:
                await self.cache_client.setex(
                    f"risk:{symbol}:{self.agent_id}",
                    1800,  # 30 minutes
                    json.dumps(risk_assessment)
                )
            
            return risk_assessment
            
        except Exception as e:
            logger.error(f"Error assessing trade risk: {e}")
            return {"error": str(e), "trade_approved": False}
    
    def check_position_limits(self, position_value: float) -> Dict[str, Any]:
        """Check if position size is within limits"""
        max_position = self.risk_limits["max_position_size"]
        
        if position_value > max_position:
            return {
                "risk_score": 1.0,
                "message": f"Position size {position_value} exceeds limit {max_position}",
                "approved": False
            }
        
        risk_ratio = position_value / max_position
        return {
            "risk_score": risk_ratio,
            "message": f"Position size OK ({risk_ratio:.2%} of limit)",
            "approved": True
        }
    
    async def calculate_portfolio_impact(self, symbol: str, quantity: float, price: float) -> Dict[str, Any]:
        """Calculate impact on overall portfolio risk"""
        try:
            # Simulate portfolio data - replace with real portfolio API
            current_portfolio = await self.get_current_portfolio()
            
            # Calculate new portfolio composition
            new_value = quantity * price
            total_portfolio_value = sum(pos['value'] for pos in current_portfolio) + new_value
            
            # Check concentration limits
            symbol_concentration = new_value / total_portfolio_value if total_portfolio_value > 0 else 0
            max_concentration = self.risk_limits["max_concentration"]
            
            if symbol_concentration > max_concentration:
                return {
                    "risk_score": 1.0,
                    "message": f"Position would create {symbol_concentration:.2%} concentration (limit: {max_concentration:.2%})",
                    "approved": False
                }
            
            return {
                "risk_score": symbol_concentration / max_concentration,
                "message": f"Portfolio concentration OK ({symbol_concentration:.2%})",
                "approved": True
            }
            
        except Exception as e:
            logger.error(f"Error calculating portfolio impact: {e}")
            return {"risk_score": 0.5, "message": "Could not calculate portfolio impact", "approved": True}
    
    async def calculate_var(self, symbol: str, quantity: float) -> Dict[str, Any]:
        """Calculate Value at Risk for the position"""
        try:
            # Simulate historical data for VaR calculation
            # In production, use real historical price data
            returns = np.random.normal(0, 0.02, 252)  # Simulate daily returns
            
            # Calculate 95% VaR
            var_95 = np.percentile(returns, 5)
            position_var = abs(quantity * var_95)
            
            max_daily_loss = self.risk_limits["max_daily_loss"]
            
            if position_var > max_daily_loss:
                return {
                    "risk_score": 1.0,
                    "var_95": position_var,
                    "message": f"VaR {position_var:.2f} exceeds daily loss limit {max_daily_loss}",
                    "approved": False
                }
            
            risk_ratio = position_var / max_daily_loss
            return {
                "risk_score": risk_ratio,
                "var_95": position_var,
                "message": f"VaR within limits ({risk_ratio:.2%} of limit)",
                "approved": True
            }
            
        except Exception as e:
            logger.error(f"Error calculating VaR: {e}")
            return {"risk_score": 0.5, "message": "Could not calculate VaR", "approved": True}
    
    async def get_current_portfolio(self) -> List[Dict[str, Any]]:
        """Get current portfolio positions"""
        # Simulate portfolio - replace with real portfolio API
        return [
            {"symbol": "AAPL", "quantity": 100, "value": 15000},
            {"symbol": "GOOGL", "quantity": 50, "value": 12000},
            {"symbol": "MSFT", "quantity": 75, "value": 10000}
        ]
    
    async def run(self):
        """Main agent loop"""
        logger.info(f"Starting risk agent main loop: {self.agent_id}")
        
        while True:
            try:
                # Monitor portfolio risk
                await self.monitor_portfolio_risk()
                
                # Send heartbeat
                await self.send_heartbeat()
                
                await asyncio.sleep(60)  # Check every minute
                
            except Exception as e:
                logger.error(f"Error in main loop: {e}")
                await asyncio.sleep(60)
    
    async def monitor_portfolio_risk(self):
        """Monitor overall portfolio risk"""
        try:
            portfolio = await self.get_current_portfolio()
            total_value = sum(pos['value'] for pos in portfolio)
            
            # Check if we're within risk limits
            # This is a simplified check - add more sophisticated risk monitoring
            
            risk_metrics = {
                "portfolio_value": total_value,
                "risk_status": "normal",
                "timestamp": datetime.now().isoformat()
            }
            
            if self.cache_client:
                await self.cache_client.setex(
                    f"portfolio_risk:{NODE_ID}",
                    300,  # 5 minutes
                    json.dumps(risk_metrics)
                )
                
        except Exception as e:
            logger.error(f"Error monitoring portfolio risk: {e}")
    
    async def send_heartbeat(self):
        """Send heartbeat to orchestrator"""
        try:
            heartbeat_data = {
                "agent_id": self.agent_id,
                "status": self.status,
                "timestamp": datetime.now().isoformat()
            }
            
            async with self.session.post(
                f"{ORCHESTRATOR_URL}/heartbeat",
                json=heartbeat_data
            ) as response:
                if response.status != 200:
                    logger.warning(f"Heartbeat failed: {response.status}")
                    
        except Exception as e:
            logger.error(f"Error sending heartbeat: {e}")
    
    async def cleanup(self):
        """Cleanup resources"""
        if self.session:
            await self.session.close()
        if self.cache_client:
            await self.cache_client.close()

async def main():
    agent = RiskAgent()
    
    try:
        await agent.initialize()
        await agent.run()
    except KeyboardInterrupt:
        logger.info("Risk agent shutting down...")
    finally:
        await agent.cleanup()

if __name__ == "__main__":
    asyncio.run(main())
EOF

# Create data collection agent
echo "📊 Creating Data Collection Agent..."
mkdir -p "$WORK_DIR/docker/data-agent"

cat > "$WORK_DIR/docker/data-agent/Dockerfile" << 'EOF'
FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

CMD ["python", "data_agent.py"]
EOF

cat > "$WORK_DIR/docker/data-agent/requirements.txt" << 'EOF'
fastapi==0.104.1
aiohttp==3.9.1
pandas==2.0.3
numpy==1.24.3
redis==5.0.1
pydantic==2.5.0
asyncio-mqtt==0.13.0
yfinance==0.2.18
alpha-vantage==2.3.1
websocket-client==1.6.1
ccxt==4.0.72
feedparser==6.0.10
beautifulsoup4==4.12.2
requests==2.31.0
schedule==1.2.0
EOF

cat > "$WORK_DIR/docker/data-agent/data_agent.py" << 'EOF'
import os
import asyncio
import aiohttp
import json
import logging
from datetime import datetime, timedelta
import pandas as pd
import numpy as np
from typing import Dict, Any, List
import redis.asyncio as redis
import yfinance as yf
import feedparser
import requests
from bs4 import BeautifulSoup

NODE_ID = os.getenv("NODE_ID", "unknown")
AGENT_TYPE = os.getenv("AGENT_TYPE", "data")
ORCHESTRATOR_URL = os.getenv("ORCHESTRATOR_URL", "http://localhost:8001")

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/app/logs/data-agent.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(f"data-agent-{NODE_ID}")

class DataAgent:
    def __init__(self):
        self.agent_id = f"data-{NODE_ID}-{datetime.now().strftime('%H%M%S')}"
        self.status = "idle"
        self.session = None
        self.cache_client = None
        self.data_sources = {
            "stocks": ["AAPL", "GOOGL", "MSFT", "AMZN", "TSLA"],
            "indices": ["^GSPC", "^DJI", "^IXIC"],
            "crypto": ["BTC-USD", "ETH-USD"],
            "news_feeds": [
                "https://feeds.bloomberg.com/markets/news.rss",
                "https://feeds.reuters.com/reuters/businessNews.xml"
            ]
        }
        
    async def initialize(self):
        """Initialize the data agent"""
        logger.info(f"Initializing data agent: {self.agent_id}")
        
        self.session = aiohttp.ClientSession()
        
        try:
            redis_url = os.getenv("REDIS_URL", "redis://host.docker.internal:6379")
            self.cache_client = redis.from_url(redis_url, decode_responses=True)
            await self.cache_client.ping()
            logger.info("Connected to Redis cache")
        except Exception as e:
            logger.error(f"Redis connection failed: {e}")
        
        await self.register_with_orchestrator()
        
    async def register_with_orchestrator(self):
        """Register this agent with the orchestrator"""
        try:
            registration_data = {
                "agent_id": self.agent_id,
                "agent_type": AGENT_TYPE,
                "capabilities": [
                    "market_data_collection",
                    "news_sentiment_analysis",
                    "economic_indicators",
                    "real_time_feeds",
                    "data_validation"
                ],
                "status": self.status
            }
            
            async with self.session.post(
                f"{ORCHESTRATOR_URL}/register",
                json=registration_data
            ) as response:
                if response.status == 200:
                    logger.info("Successfully registered with orchestrator")
                else:
                    logger.error(f"Failed to register: {response.status}")
                    
        except Exception as e:
            logger.error(f"Error registering with orchestrator: {e}")
    
    async def collect_market_data(self) -> Dict[str, Any]:
        """Collect market data for tracked symbols"""
        try:
            logger.info("Collecting market data...")
            
            market_data = {}
            
            # Collect stock data
            for symbol in self.data_sources["stocks"]:
                try:
                    ticker = yf.Ticker(symbol)
                    hist = ticker.history(period="1d", interval="1m")
                    
                    if not hist.empty:
                        latest = hist.iloc[-1]
                        market_data[symbol] = {
                            "price": float(latest['Close']),
                            "volume": int(latest['Volume']),
                            "high": float(latest['High']),
                            "low": float(latest['Low']),
                            "timestamp": datetime.now().isoformat()
                        }
                        
                        # Cache the data
                        if self.cache_client:
                            await self.cache_client.setex(
                                f"market_data:{symbol}",
                                300,  # 5 minutes
                                json.dumps(market_data[symbol])
                            )
                            
                except Exception as e:
                    logger.error(f"Error collecting data for {symbol}: {e}")
            
            return market_data
            
        except Exception as e:
            logger.error(f"Error collecting market data: {e}")
            return {}
    
    async def collect_news_sentiment(self) -> List[Dict[str, Any]]:
        """Collect and analyze news sentiment"""
        try:
            logger.info("Collecting news sentiment...")
            
            news_items = []
            
            for feed_url in self.data_sources["news_feeds"]:
                try:
                    feed = feedparser.parse(feed_url)
                    
                    for entry in feed.entries[:5]:  # Get latest 5 items
                        news_item = {
                            "title": entry.title,
                            "summary": entry.summary if hasattr(entry, 'summary') else "",
                            "published": entry.published if hasattr(entry, 'published') else "",
                            "link": entry.link,
                            "sentiment": self.analyze_sentiment(entry.title + " " + getattr(entry, 'summary', '')),
                            "source": feed_url,
                            "timestamp": datetime.now().isoformat()
                        }
                        news_items.append(news_item)
                        
                except Exception as e:
                    logger.error(f"Error processing feed {feed_url}: {e}")
            
            # Cache news sentiment
            if self.cache_client and news_items:
                await self.cache_client.setex(
                    f"news_sentiment:{NODE_ID}",
                    1800,  # 30 minutes
                    json.dumps(news_items)
                )
            
            return news_items
            
        except Exception as e:
            logger.error(f"Error collecting news sentiment: {e}")
            return []
    
    def analyze_sentiment(self, text: str) -> Dict[str, Any]:
        """Simple sentiment analysis (replace with proper NLP model)"""
        # Simplified sentiment analysis
        positive_words = ['up', 'gain', 'rise', 'bull', 'positive', 'growth', 'profit']
        negative_words = ['down', 'loss', 'fall', 'bear', 'negative', 'decline', 'crash']
        
        text_lower = text.lower()
        positive_count = sum(1 for word in positive_words if word in text_lower)
        negative_count = sum(1 for word in negative_words if word in text_lower)
        
        if positive_count > negative_count:
            sentiment = "positive"
            score = min(positive_count / (positive_count + negative_count + 1), 1.0)
        elif negative_count > positive_count:
            sentiment = "negative"
            score = -min(negative_count / (positive_count + negative_count + 1), 1.0)
        else:
            sentiment = "neutral"
            score = 0.0
        
        return {
            "sentiment": sentiment,
            "score": score,
            "positive_signals": positive_count,
            "negative_signals": negative_count
        }
    
    async def validate_data_quality(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Validate quality of collected data"""
        validation_results = {
            "total_symbols": len(data),
            "valid_symbols": 0,
            "missing_data": [],
            "quality_score": 0.0,
            "timestamp": datetime.now().isoformat()
        }
        
        for symbol, symbol_data in data.items():
            if all(key in symbol_data for key in ['price', 'volume', 'timestamp']):
                if symbol_data['price'] > 0 and symbol_data['volume'] >= 0:
                    validation_results["valid_symbols"] += 1
                else:
                    validation_results["missing_data"].append(f"{symbol}: invalid values")
            else:
                validation_results["missing_data"].append(f"{symbol}: missing fields")
        
        if validation_results["total_symbols"] > 0:
            validation_results["quality_score"] = validation_results["valid_symbols"] / validation_results["total_symbols"]
        
        return validation_results
    
    async def run(self):
        """Main agent loop"""
        logger.info(f"Starting data agent main loop: {self.agent_id}")
        
        while True:
            try:
                # Collect market data every 5 minutes
                if datetime.now().minute % 5 == 0:
                    market_data = await self.collect_market_data()
                    validation = await self.validate_data_quality(market_data)
                    logger.info(f"Collected data for {validation['valid_symbols']} symbols (quality: {validation['quality_score']:.2%})")
                
                # Collect news sentiment every 30 minutes
                if datetime.now().minute % 30 == 0:
                    news_sentiment = await self.collect_news_sentiment()
                    logger.info(f"Collected {len(news_sentiment)} news items")
                
                # Send heartbeat
                await self.send_heartbeat()
                
                await asyncio.sleep(60)  # Check every minute
                
            except Exception as e:
                logger.error(f"Error in main loop: {e}")
                await asyncio.sleep(60)
    
    async def send_heartbeat(self):
        """Send heartbeat to orchestrator"""
        try:
            heartbeat_data = {
                "agent_id": self.agent_id,
                "status": self.status,
                "timestamp": datetime.now().isoformat()
            }
            
            async with self.session.post(
                f"{ORCHESTRATOR_URL}/heartbeat",
                json=heartbeat_data
            ) as response:
                if response.status != 200:
                    logger.warning(f"Heartbeat failed: {response.status}")
                    
        except Exception as e:
            logger.error(f"Error sending heartbeat: {e}")
    
    async def cleanup(self):
        """Cleanup resources"""
        if self.session:
            await self.session.close()
        if self.cache_client:
            await self.cache_client.close()

async def main():
    agent = DataAgent()
    
    try:
        await agent.initialize()
        await agent.run()
    except KeyboardInterrupt:
        logger.info("Data agent shutting down...")
    finally:
        await agent.cleanup()

if __name__ == "__main__":
    asyncio.run(main())
EOF

# Create monitoring service
echo "📈 Creating Monitoring Service..."
mkdir -p "$WORK_DIR/docker/monitoring"

cat > "$WORK_DIR/docker/monitoring/Dockerfile" << 'EOF'
FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 9090

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "9090"]
EOF

cat > "$WORK_DIR/docker/monitoring/requirements.txt" << 'EOF'
fastapi==0.104.1
uvicorn==0.24.0
prometheus-client==0.19.0
psutil==5.9.6
docker==6.1.3
aiohttp==3.9.1
redis==5.0.1
asyncpg==0.29.0
pydantic==2.5.0
jinja2==3.1.2
EOF

cat > "$WORK_DIR/docker/monitoring/main.py" << 'EOF'
import os
import asyncio
import docker
from fastapi import FastAPI, Response
from fastapi.responses import HTMLResponse
import psutil
import json
import logging
from datetime import datetime
from typing import Dict, Any
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST
import redis.asyncio as redis

NODE_ID = os.getenv("NODE_ID", "unknown")
MESH_IP = os.getenv("MESH_IP", "127.0.0.1")

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/app/logs/monitoring.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(f"monitoring-{NODE_ID}")

app = FastAPI(title=f"Monitoring Service {NODE_ID}")

# Prometheus metrics
system_cpu_usage = Gauge('system_cpu_usage_percent', 'System CPU usage percentage')
system_memory_usage = Gauge('system_memory_usage_percent', 'System memory usage percentage')
system_disk_usage = Gauge('system_disk_usage_percent', 'System disk usage percentage')
docker_containers_running = Gauge('docker_containers_running', 'Number of running Docker containers')
agent_heartbeats = Counter('agent_heartbeats_total', 'Total agent heartbeats', ['agent_type'])

# Docker client
docker_client = None
cache_client = None

@app.on_event("startup")
async def startup_event():
    global docker_client, cache_client
    
    logger.info(f"Starting monitoring service on node: {NODE_ID}")
    
    try:
        docker_client = docker.from_env()
        logger.info("Connected to Docker daemon")
    except Exception as e:
        logger.error(f"Docker connection failed: {e}")
    
    try:
        redis_url = os.getenv("REDIS_URL", "redis://host.docker.internal:6379")
        cache_client = redis.from_url(redis_url, decode_responses=True)
        await cache_client.ping()
        logger.info("Connected to Redis cache")
    except Exception as e:
        logger.error(f"Redis connection failed: {e}")
    
    # Start monitoring loop
    asyncio.create_task(monitoring_loop())

async def monitoring_loop():
    """Main monitoring loop"""
    while True:
        try:
            await collect_system_metrics()
            await collect_docker_metrics()
            await asyncio.sleep(30)  # Collect metrics every 30 seconds
        except Exception as e:
            logger.error(f"Error in monitoring loop: {e}")
            await asyncio.sleep(30)

async def collect_system_metrics():
    """Collect system performance metrics"""
    try:
        # CPU usage
        cpu_percent = psutil.cpu_percent(interval=1)
        system_cpu_usage.set(cpu_percent)
        
        # Memory usage
        memory = psutil.virtual_memory()
        system_memory_usage.set(memory.percent)
        
        # Disk usage
        disk = psutil.disk_usage('/')
        system_disk_usage.set(disk.percent)
        
        # Store in cache for dashboard
        metrics = {
            "cpu_percent": cpu_percent,
            "memory_percent": memory.percent,
            "disk_percent": disk.percent,
            "timestamp": datetime.now().isoformat()
        }
        
        if cache_client:
            await cache_client.setex(
                f"system_metrics:{NODE_ID}",
                60,
                json.dumps(metrics)
            )
            
    except Exception as e:
        logger.error(f"Error collecting system metrics: {e}")

async def collect_docker_metrics():
    """Collect Docker container metrics"""
    try:
        if docker_client:
            containers = docker_client.containers.list()
            running_containers = len([c for c in containers if c.status == 'running'])
            docker_containers_running.set(running_containers)
            
            # Store container info in cache
            container_info = []
            for container in containers:
                info = {
                    "name": container.name,
                    "status": container.status,
                    "image": container.image.tags[0] if container.image.tags else "unknown"
                }
                container_info.append(info)
            
            if cache_client:
                await cache_client.setex(
                    f"docker_metrics:{NODE_ID}",
                    60,
                    json.dumps(container_info)
                )
                
    except Exception as e:
        logger.error(f"Error collecting Docker metrics: {e}")

@app.get("/metrics")
async def metrics():
    """Prometheus metrics endpoint"""
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {
        "node_id": NODE_ID,
        "status": "operational",
        "timestamp": datetime.now().isoformat()
    }

@app.get("/dashboard", response_class=HTMLResponse)
async def dashboard():
    """Simple monitoring dashboard"""
    try:
        # Get latest metrics from cache
        system_metrics = {}
        docker_metrics = []
        
        if cache_client:
            system_data = await cache_client.get(f"system_metrics:{NODE_ID}")
            if system_data:
                system_metrics = json.loads(system_data)
            
            docker_data = await cache_client.get(f"docker_metrics:{NODE_ID}")
            if docker_data:
                docker_metrics = json.loads(docker_data)
        
        html_content = f"""
        <!DOCTYPE html>
        <html>
        <head>
            <title>Monitoring Dashboard - Node {NODE_ID}</title>
            <meta http-equiv="refresh" content="30">
            <style>
                body {{ font-family: Arial, sans-serif; margin: 20px; }}
                .metric {{ background: #f5f5f5; padding: 15px; margin: 10px 0; border-radius: 5px; }}
                .container {{ display: flex; flex-wrap: wrap; gap: 20px; }}
                .panel {{ flex: 1; min-width: 300px; }}
                .status-ok {{ color: green; }}
                .status-warning {{ color: orange; }}
                .status-error {{ color: red; }}
            </style>
        </head>
        <body>
            <h1>Monitoring Dashboard - Node {NODE_ID}</h1>
            <p>Last updated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
            
            <div class="container">
                <div class="panel">
                    <h2>System Metrics</h2>
                    <div class="metric">
                        <strong>CPU Usage:</strong> {system_metrics.get('cpu_percent', 'N/A')}%
                    </div>
                    <div class="metric">
                        <strong>Memory Usage:</strong> {system_metrics.get('memory_percent', 'N/A')}%
                    </div>
                    <div class="metric">
                        <strong>Disk Usage:</strong> {system_metrics.get('disk_percent', 'N/A')}%
                    </div>
                </div>
                
                <div class="panel">
                    <h2>Docker Containers</h2>
                    {''.join([f'<div class="metric"><strong>{c["name"]}:</strong> {c["status"]} ({c["image"]})</div>' for c in docker_metrics])}
                </div>
            </div>
            
            <div class="panel">
                <h2>Network Info</h2>
                <div class="metric">
                    <strong>Node ID:</strong> {NODE_ID}<br>
                    <strong>Mesh IP:</strong> {MESH_IP}
                </div>
            </div>
        </body>
        </html>
        """
        
        return html_content
        
    except Exception as e:
        logger.error(f"Error generating dashboard: {e}")
        return f"<html><body><h1>Dashboard Error</h1><p>{str(e)}</p></body></html>"

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=9090, log_level="info")
EOF

echo "✅ Docker agent templates created successfully!"
echo ""
echo "📂 Created agents:"
echo "   • Trading Agent: $WORK_DIR/docker/trading-agent/"
echo "   • Risk Agent: $WORK_DIR/docker/risk-agent/"
echo "   • Data Agent: $WORK_DIR/docker/data-agent/"
echo "   • Monitoring Service: $WORK_DIR/docker/monitoring/"
echo ""
echo "🔄 To rebuild and restart with new agents:"
echo "   cd $WORK_DIR && ./manage.sh build && ./manage.sh restart"
echo ""
echo "📊 To view logs for specific agent:"
echo "   $WORK_DIR/manage.sh logs trading-agent"
echo "   $WORK_DIR/manage.sh logs risk-agent"
echo "   $WORK_DIR/manage.sh logs data-agent" 