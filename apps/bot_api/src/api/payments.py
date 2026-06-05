from __future__ import annotations

from fastapi import APIRouter, Depends, Header, HTTPException, Request, status
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from src.config import settings
from src.db.session import get_db
from src.dependencies.auth import verify_internal_api_key
from src.repositories.payments import PaymentsRepository
from src.schemas.payments import (
    PaymentCreateRequest,
    PaymentCreateResponse,
    PaymentResponse,
    PaymentStatusResponse,
    PaymentWebhookRequest,
)


router = APIRouter(prefix="/payments", tags=["payments"])


def _validate_webhook_security(
    payload: PaymentWebhookRequest,
    x_webhook_secret: str | None,
) -> None:
    if settings.PAYMENT_WEBHOOK_SECRET:
        if x_webhook_secret != settings.PAYMENT_WEBHOOK_SECRET and not payload.signature:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid webhook secret",
            )


@router.post(
    "/create",
    response_model=PaymentCreateResponse,
    dependencies=[Depends(verify_internal_api_key)],
)
def create_payment(
    payload: PaymentCreateRequest,
    db: Session = Depends(get_db),
) -> PaymentCreateResponse:
    repo = PaymentsRepository(db)

    try:
        payment, payment_url, invoice_url = repo.create_for_telegram_user(payload)

    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        ) from exc

    except LookupError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(exc),
        ) from exc

    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Payment already exists or violates unique constraints",
        ) from exc

    return PaymentCreateResponse(
        id=payment.id,
        provider=payment.provider,
        status=payment.status,
        amount=payment.amount,
        currency=payment.currency,
        external_payment_id=payment.external_payment_id,
        idempotency_key=payment.idempotency_key,
        payment_url=payment_url,
        invoice_url=invoice_url,
        return_url=payment.return_url,
        success_url=payment.success_url,
        fail_url=payment.fail_url,
        created_at=payment.created_at,
    )


@router.post("/webhook", response_model=PaymentResponse)
async def payment_webhook(
    payload: PaymentWebhookRequest,
    request: Request,
    x_webhook_secret: str | None = Header(default=None),
    db: Session = Depends(get_db),
) -> PaymentResponse:
    _validate_webhook_security(payload, x_webhook_secret)

    if payload.transaction_id and not payload.event_id:
        payload.event_id = payload.transaction_id

    repo = PaymentsRepository(db)

    try:
        payment = repo.apply_webhook(payload)

    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        ) from exc

    except PermissionError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(exc),
        ) from exc

    if not payment:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Payment not found",
        )

    return PaymentResponse.model_validate(payment)


@router.get(
    "/{payment_id}",
    response_model=PaymentResponse,
    dependencies=[Depends(verify_internal_api_key)],
)
def get_payment(
    payment_id: int,
    db: Session = Depends(get_db),
) -> PaymentResponse:
    repo = PaymentsRepository(db)
    payment = repo.get_by_id(payment_id)

    if not payment:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Payment not found",
        )

    return PaymentResponse.model_validate(payment)


@router.get(
    "/{payment_id}/status",
    response_model=PaymentStatusResponse,
    dependencies=[Depends(verify_internal_api_key)],
)
def get_payment_status(
    payment_id: int,
    db: Session = Depends(get_db),
) -> PaymentStatusResponse:
    repo = PaymentsRepository(db)
    payment = repo.get_by_id(payment_id)

    if not payment:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Payment not found",
        )

    return PaymentStatusResponse(
        id=payment.id,
        provider=payment.provider,
        status=payment.status,
        amount=payment.amount,
        currency=payment.currency,
        external_payment_id=payment.external_payment_id,
        idempotency_key=payment.idempotency_key,
        payment_url=payment.payment_url,
        invoice_url=payment.invoice_url,
        paid_at=payment.paid_at,
        created_at=payment.created_at,
        updated_at=payment.updated_at,
    )