#!/usr/bin/env python3
"""
Ursus Data Logger for Cryonith LLC
Pushes trading data from Pi to AWS DynamoDB
Phase 1: Hybrid Data Backend
"""

import boto3
import json
import logging
import os
import uuid
from datetime import datetime, timezone
from decimal import Decimal
import time
import asyncio
from dataclasses import dataclass, asdict
from typing import Dict, List, Optional, Any
import threading
from queue import Queue

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('UrsusDataLogger')

@dataclass
class TradeLog:
    """Trade execution log entry"""
    trade_id: str
    timestamp: str
    strategy: str
    symbol: str
    action: str  # 'BUY', 'SELL', 'HOLD'
    quantity: float
    price: float
    confidence: float
    market_signal: str
    execution_time_ms: float
    profit_loss: Optional[float] = None
    portfolio_value: Optional[float] = None
    
@dataclass 
class StrategyMetric:
    """Strategy performance metrics"""
    strategy_id: str
    timestamp: str
    win_rate: float
    total_trades: int
    profit_loss: float
    sharpe_ratio: float
    max_drawdown: float
    current_positions: int
    avg_hold_time: float
    
@dataclass
class MarketSignal:
    """Market analysis signal"""
    signal_id: str
    timestamp: str
    symbol: str
    signal_type: str  # 'BUY', 'SELL', 'NEUTRAL'
    strength: float  # 0.0 to 1.0
    indicators: Dict[str, float]
    news_sentiment: Optional[float] = None
    volume_analysis: Optional[float] = None

class UrsusDataLogger:
    """Main data logger class for Ursus trading system"""
    
    def __init__(self, region_name='us-east-1'):
        self.region_name = region_name
        self.session = boto3.Session(
            aws_access_key_id=os.getenv('AWS_ACCESS_KEY_ID'),
            aws_secret_access_key=os.getenv('AWS_SECRET_ACCESS_KEY'),
            region_name=region_name
        )
        self.dynamodb = self.session.resource('dynamodb')
        
        # Initialize tables
        self.trade_logs_table = self.dynamodb.Table('CryonithTradeLogs')
        self.strategy_metrics_table = self.dynamodb.Table('CryonithStrategyMetrics')
        self.market_signals_table = self.dynamodb.Table('CryonithMarketSignals')
        self.performance_table = self.dynamodb.Table('CryonithPerformance')
        
        # Queue for batch processing
        self.data_queue = Queue()
        self.batch_size = 25  # DynamoDB batch limit
        self.flush_interval = 30  # seconds
        
        # Start background processor
        self.running = True
        self.processor_thread = threading.Thread(target=self._batch_processor)
        self.processor_thread.daemon = True
        self.processor_thread.start()
        
        logger.info("🚀 Ursus Data Logger initialized")
        
    def log_trade(self, trade: TradeLog) -> bool:
        """Log a trade execution"""
        try:
            item = self._convert_decimals(asdict(trade))
            self.trade_logs_table.put_item(Item=item)
            logger.info(f"📊 Trade logged: {trade.trade_id} - {trade.action} {trade.symbol}")
            return True
        except Exception as e:
            logger.error(f"❌ Failed to log trade: {e}")
            return False
    
    def log_strategy_metrics(self, metrics: StrategyMetric) -> bool:
        """Log strategy performance metrics"""
        try:
            item = self._convert_decimals(asdict(metrics))
            self.strategy_metrics_table.put_item(Item=item)
            logger.info(f"🧠 Strategy metrics logged: {metrics.strategy_id}")
            return True
        except Exception as e:
            logger.error(f"❌ Failed to log strategy metrics: {e}")
            return False
    
    def log_market_signal(self, signal: MarketSignal) -> bool:
        """Log market analysis signal"""
        try:
            item = self._convert_decimals(asdict(signal))
            self.market_signals_table.put_item(Item=item)
            logger.info(f"📡 Market signal logged: {signal.signal_id} - {signal.signal_type}")
            return True
        except Exception as e:
            logger.error(f"❌ Failed to log market signal: {e}")
            return False
    
    def log_daily_performance(self, date: str, metrics: Dict[str, float]) -> bool:
        """Log daily performance metrics"""
        try:
            item = {
                'MetricType': 'DAILY_PERFORMANCE',
                'Date': date,
                **self._convert_decimals(metrics),
                'Timestamp': datetime.now(timezone.utc).isoformat()
            }
            self.performance_table.put_item(Item=item)
            logger.info(f"📈 Daily performance logged for {date}")
            return True
        except Exception as e:
            logger.error(f"❌ Failed to log daily performance: {e}")
            return False
    
    def batch_log_trades(self, trades: List[TradeLog]) -> int:
        """Batch log multiple trades for efficiency"""
        success_count = 0
        
        # Process in batches of 25 (DynamoDB limit)
        for i in range(0, len(trades), self.batch_size):
            batch = trades[i:i + self.batch_size]
            try:
                with self.trade_logs_table.batch_writer() as batch_writer:
                    for trade in batch:
                        item = self._convert_decimals(asdict(trade))
                        batch_writer.put_item(Item=item)
                        success_count += 1
                logger.info(f"📊 Batch logged {len(batch)} trades")
            except Exception as e:
                logger.error(f"❌ Failed to batch log trades: {e}")
        
        return success_count
    
    def get_strategy_performance(self, strategy_id: str, days: int = 7) -> List[Dict]:
        """Get recent strategy performance data"""
        try:
            from datetime import timedelta
            end_date = datetime.now(timezone.utc)
            start_date = end_date - timedelta(days=days)
            
            response = self.strategy_metrics_table.query(
                KeyConditionExpression=boto3.dynamodb.conditions.Key('StrategyId').eq(strategy_id) &
                                     boto3.dynamodb.conditions.Key('Timestamp').between(
                                         start_date.isoformat(),
                                         end_date.isoformat()
                                     )
            )
            return response.get('Items', [])
        except Exception as e:
            logger.error(f"❌ Failed to get strategy performance: {e}")
            return []
    
    def get_recent_trades(self, hours: int = 24) -> List[Dict]:
        """Get recent trades across all strategies"""
        try:
            from datetime import timedelta
            cutoff_time = datetime.now(timezone.utc) - timedelta(hours=hours)
            
            response = self.trade_logs_table.scan(
                FilterExpression=boto3.dynamodb.conditions.Attr('timestamp').gte(cutoff_time.isoformat())
            )
            return response.get('Items', [])
        except Exception as e:
            logger.error(f"❌ Failed to get recent trades: {e}")
            return []
    
    def _convert_decimals(self, data: Any) -> Any:
        """Convert floats to Decimal for DynamoDB"""
        if isinstance(data, dict):
            return {k: self._convert_decimals(v) for k, v in data.items()}
        elif isinstance(data, list):
            return [self._convert_decimals(item) for item in data]
        elif isinstance(data, float):
            return Decimal(str(data))
        return data
    
    def _batch_processor(self):
        """Background thread for batch processing queued data"""
        while self.running:
            try:
                time.sleep(self.flush_interval)
                # Process any queued data here if needed
                pass
            except Exception as e:
                logger.error(f"❌ Batch processor error: {e}")
    
    def shutdown(self):
        """Gracefully shutdown the logger"""
        self.running = False
        if self.processor_thread.is_alive():
            self.processor_thread.join(timeout=5)
        logger.info("🛑 Ursus Data Logger shutdown complete")

# Example usage and testing functions
def simulate_ursus_trading():
    """Simulate Ursus trading activity for testing"""
    logger = UrsusDataLogger()
    
    # Simulate a trade
    trade = TradeLog(
        trade_id=str(uuid.uuid4()),
        timestamp=datetime.now(timezone.utc).isoformat(),
        strategy="ursus_momentum_v1",
        symbol="TSLA",
        action="BUY",
        quantity=100.0,
        price=245.50,
        confidence=0.85,
        market_signal="BULLISH_MOMENTUM",
        execution_time_ms=150.5,
        portfolio_value=50000.0
    )
    
    # Log the trade
    success = logger.log_trade(trade)
    print(f"Trade logging: {'✅ Success' if success else '❌ Failed'}")
    
    # Simulate strategy metrics
    metrics = StrategyMetric(
        strategy_id="ursus_momentum_v1",
        timestamp=datetime.now(timezone.utc).isoformat(),
        win_rate=0.68,
        total_trades=45,
        profit_loss=2750.50,
        sharpe_ratio=1.85,
        max_drawdown=0.12,
        current_positions=3,
        avg_hold_time=4.5
    )
    
    logger.log_strategy_metrics(metrics)
    
    # Simulate market signal
    signal = MarketSignal(
        signal_id=str(uuid.uuid4()),
        timestamp=datetime.now(timezone.utc).isoformat(),
        symbol="TSLA",
        signal_type="BUY",
        strength=0.82,
        indicators={
            "rsi": 65.4,
            "macd": 2.3,
            "volume_sma": 1.25,
            "price_momentum": 0.15
        },
        news_sentiment=0.7
    )
    
    logger.log_market_signal(signal)
    
    return logger

if __name__ == "__main__":
    # Test the logger
    print("🧪 Testing Ursus Data Logger...")
    
    # Check environment variables
    required_vars = ['AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY']
    missing_vars = [var for var in required_vars if not os.getenv(var)]
    
    if missing_vars:
        print(f"❌ Missing environment variables: {missing_vars}")
        print("Set them with:")
        for var in missing_vars:
            print(f"export {var}=your_value_here")
        exit(1)
    
    try:
        # Run simulation
        logger = simulate_ursus_trading()
        print("✅ Ursus Data Logger test completed successfully!")
        
        # Get recent data to verify
        recent_trades = logger.get_recent_trades(1)
        print(f"📊 Recent trades in last hour: {len(recent_trades)}")
        
        logger.shutdown()
        
    except Exception as e:
        print(f"❌ Test failed: {e}")
        exit(1) 