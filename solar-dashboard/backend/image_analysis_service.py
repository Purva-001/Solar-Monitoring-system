"""
FastAPI service for solar panel image analysis using ML model and RAG
Runs on port 8000 with CORS enabled for React frontend on port 3000
"""

import os
import sys
import logging
from io import BytesIO
from typing import Optional
from pathlib import Path
from dotenv import load_dotenv

import cv2
import numpy as np
from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
import json

# Load environment variables from .env file
env_path = Path(__file__).parent.parent.parent / '.env'
load_dotenv(env_path)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('ImageAnalysisService')

# Add parent directory to path for imports
# Current: solar-dashboard/backend/
# Parent: ../.. goes to rag_folder
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))

# Import ML components
try:
    from backend.onnx_infer import predict_image_bytes
    logger.info("✓ Imported ONNX inference module")
except ImportError as e:
    logger.warning(f"✗ Could not import onnx_infer: {e}")
    predict_image_bytes = None

try:
    from rag_module.query import query_rag, build_query_from_ml_output
    from rag_module.vectorstores.faiss_store import FAISSStore
    logger.info("✓ Imported RAG modules")
except ImportError as e:
    logger.warning(f"✗ Could not import RAG modules: {e}")
    query_rag = None

try:
    import google.generativeai as genai
    # Try to get API key from environment or .env file
    GEMINI_API_KEY = os.environ.get('GEMINI_API_KEY') or os.environ.get('GEMINI_API_KEYS')
    if GEMINI_API_KEY and ',' in GEMINI_API_KEY:
        # If multiple keys (comma-separated), use the first one and strip all whitespace
        keys = [k.strip() for k in GEMINI_API_KEY.split(',')]
        GEMINI_API_KEY = keys[0]
        logger.info(f"Multiple API keys found, using key #1")
    elif GEMINI_API_KEY:
        GEMINI_API_KEY = GEMINI_API_KEY.strip()
    
    if GEMINI_API_KEY:
        genai.configure(api_key=GEMINI_API_KEY)
        logger.info(f"✓ Gemini API configured with key: {GEMINI_API_KEY[:20]}...")
    else:
        logger.warning("✗ GEMINI_API_KEY not set")
except ImportError as e:
    logger.warning(f"✗ Could not import Gemini: {e}")
    genai = None

# Initialize FastAPI app
app = FastAPI(
    title="Solar Panel Image Analysis Service",
    description="Analyzes solar panel images using ML model, RAG, and Gemini AI",
    version="1.0.0"
)

# Enable CORS for React frontend
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000", "http://127.0.0.1:3000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

logger.info("✓ CORS enabled for localhost:3000")

# Setup paths - point to parent directory (rag_folder)
ONNX_MODEL_PATH = os.path.join(os.path.dirname(__file__), '..', '..', 'models', 'last.onnx')
FAISS_PATH = os.path.join(os.path.dirname(__file__), '..', '..', 'vector_db', 'faiss')

logger.info(f"Model path: {ONNX_MODEL_PATH}")
logger.info(f"FAISS path: {FAISS_PATH}")
logger.info(f"Model exists: {os.path.exists(ONNX_MODEL_PATH)}")


def resize_image(image_bytes: bytes, max_width: int = 640, max_height: int = 640) -> bytes:
    """
    Resize image to prevent timeout and reduce processing time
    
    Args:
        image_bytes: Raw image bytes
        max_width: Maximum width in pixels
        max_height: Maximum height in pixels
    
    Returns:
        Resized image bytes
    """
    try:
        # Load image from bytes
        nparr = np.frombuffer(image_bytes, np.uint8)
        img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        
        if img is None:
            raise ValueError("Could not decode image")
        
        # Get original dimensions
        height, width = img.shape[:2]
        logger.info(f"Original image size: {width}x{height}")
        
        # Calculate scaling factor
        scale = min(max_width / width, max_height / height, 1.0)
        
        if scale < 1.0:
            new_width = int(width * scale)
            new_height = int(height * scale)
            img = cv2.resize(img, (new_width, new_height), interpolation=cv2.INTER_AREA)
            logger.info(f"Resized to: {new_width}x{new_height}")
        
        # Encode back to bytes
        _, buffer = cv2.imencode('.jpg', img, [cv2.IMWRITE_JPEG_QUALITY, 85])
        return buffer.tobytes()
    
    except Exception as e:
        logger.error(f"Error resizing image: {e}")
        raise


@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "model_available": os.path.exists(ONNX_MODEL_PATH),
        "rag_available": os.path.exists(FAISS_PATH),
        "gemini_configured": GEMINI_API_KEY is not None
    }


async def _analyze_image_impl(
    image: UploadFile = File(...),
    panel_id: str = Form("Unknown")
):
    """
    Analyze a solar panel image using ML model, RAG, and Gemini AI
    
    Args:
        image: Image file (JPEG, PNG, etc.)
        panel_id: Solar panel identifier
    
    Returns:
        JSON with analysis results
    """
    logger.info(f"[ANALYZE] Received request for panel: {panel_id}")
    
    try:
        # Validate file
        if not image.filename:
            logger.warning("No filename provided")
            raise HTTPException(status_code=400, detail="No image file provided")
        
        # Read and validate image
        logger.info(f"Reading image: {image.filename}")
        image_bytes = await image.read()
        
        if not image_bytes:
            logger.warning("Empty image file")
            raise HTTPException(status_code=400, detail="Image file is empty")
        
        logger.info(f"Original image size: {len(image_bytes)} bytes")
        
        # Resize image to prevent timeout
        logger.info("Resizing image...")
        image_bytes = resize_image(image_bytes, max_width=640, max_height=640)
        logger.info(f"Resized image size: {len(image_bytes)} bytes")
        
        # ML Inference
        if not predict_image_bytes:
            logger.error("ML model not available")
            raise HTTPException(status_code=503, detail="ML model service unavailable")
        
        logger.info("Running ML inference...")
        try:
            fault, confidence, top_predictions = predict_image_bytes(
                model_path=ONNX_MODEL_PATH,
                image_bytes=image_bytes,
                top_k=3
            )
            logger.info(f"[ML] Detected: {fault}, Confidence: {confidence:.4f}")
        except Exception as e:
            logger.error(f"[ML] Inference failed: {e}")
            raise HTTPException(status_code=500, detail=f"ML inference failed: {str(e)}")
        
        # Build model output for RAG
        model_output = {
            'panel_id': panel_id,
            'primary_defect': fault,
            'confidence': float(confidence),
            'top_predictions': top_predictions
        }
        
        # RAG Query
        rag_context = "Knowledge base not available"
        if query_rag and os.path.exists(FAISS_PATH):
            logger.info("Querying RAG...")
            try:
                store = FAISSStore(index_path=FAISS_PATH)
                rag_context = query_rag(store, model_output=model_output, k=5)
                logger.info("[RAG] Context retrieved successfully")
            except Exception as e:
                logger.warning(f"[RAG] Query failed: {e}")
        
        # Gemini Analysis
        gemini_analysis = "Analysis unavailable"
        if genai and GEMINI_API_KEY:
            logger.info("Generating Gemini analysis...")
            try:
                model = genai.GenerativeModel('gemini-pro')
                prompt = f"""You are a solar panel expert analyzing defect detection results.

Panel ID: {panel_id}
Detected Defect: {fault}
Confidence: {confidence*100:.2f}%

Top Predictions:
{json.dumps(top_predictions, indent=2)}

Knowledge Base Context:
{rag_context}

Based on this information, provide a brief analysis including:
1. What defect was detected and confidence level
2. Potential impact on panel performance
3. Recommended maintenance action
4. Urgency level (Low/Medium/High)"""
                
                response = model.generate_content(prompt, timeout=30)
                gemini_analysis = response.text
                logger.info("[Gemini] Analysis generated successfully")
            except Exception as e:
                logger.warning(f"[Gemini] Analysis failed: {e}")
                gemini_analysis = f"Error generating analysis: {str(e)}"
        else:
            logger.warning("[Gemini] Not configured or unavailable")
        
        # Return results
        result = {
            'success': True,
            'panel_id': panel_id,
            'ml_result': {
                'fault_type': fault,
                'confidence': float(confidence),
                'top_predictions': top_predictions
            },
            'rag_context': rag_context[:500],  # Truncate for response size
            'gemini_analysis': gemini_analysis,
            'timestamp': __import__('datetime').datetime.now().isoformat()
        }
        
        logger.info(f"[ANALYZE] Analysis complete for {panel_id}")
        return JSONResponse(status_code=200, content=result)
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"[ANALYZE] Unexpected error: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Analysis failed: {str(e)}")


@app.get("/")
async def root():
    """Root endpoint with API info"""
    return {
        "service": "Solar Panel Image Analysis",
        "endpoints": {
            "health": "GET /health",
            "analyze": "POST /analyze-image"
        },
        "status": "running on port 8000"
    }


@app.post("/analyze")
async def analyze(
    image: UploadFile = File(...),
    panel_id: str = Form("Unknown")
):
    """Main analyze endpoint (alias for /analyze-image)"""
    return await _analyze_image_impl(image, panel_id)


@app.post("/analyze-image")
async def analyze_image(
    image: UploadFile = File(...),
    panel_id: str = Form("Unknown")
):
    """Analyze a solar panel image using ML model, RAG, and Gemini AI (legacy endpoint)"""
    return await _analyze_image_impl(image, panel_id)


if __name__ == "__main__":
    import uvicorn
    
    logger.info("=" * 60)
    logger.info("Starting Image Analysis Service")
    logger.info("=" * 60)
    logger.info(f"FastAPI running on http://0.0.0.0:8000")
    logger.info(f"CORS enabled for http://localhost:3000")
    logger.info("=" * 60)
    
    uvicorn.run(
        "image_analysis_service:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
        log_level="info"
    )
