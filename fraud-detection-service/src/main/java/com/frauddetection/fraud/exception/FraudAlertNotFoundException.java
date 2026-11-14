package com.frauddetection.fraud.exception;

public class FraudAlertNotFoundException extends RuntimeException {
    public FraudAlertNotFoundException(String paymentId) {
        super("Fraud alert not found for payment: " + paymentId);
    }
}
