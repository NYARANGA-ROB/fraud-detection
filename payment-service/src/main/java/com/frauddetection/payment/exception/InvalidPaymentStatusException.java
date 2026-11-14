package com.frauddetection.payment.exception;

public class InvalidPaymentStatusException extends IllegalArgumentException {
    public InvalidPaymentStatusException(String status) {
        super("Invalid payment status: " + status);
    }
}
