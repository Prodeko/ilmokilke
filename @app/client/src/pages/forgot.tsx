import React, { useCallback, useEffect, useRef, useState } from "react";
import UserOutlined from "@ant-design/icons/UserOutlined";
import { ApolloError } from "@apollo/client";
import { AuthRestrict, SharedLayout } from "@app/components";
import { useForgotPasswordMutation, useSharedQuery } from "@app/graphql";
import { extractError, getCodeFromError } from "@app/lib";
import * as Sentry from "@sentry/react";
import { Alert, Button, Form, Input } from "antd";
import { useForm } from "antd/lib/form/Form";
import { NextPage } from "next";
import Link from "next/link";

const ForgotPassword: NextPage = () => {
  const [error, setError] = useState<Error | ApolloError | null>(null);
  const query = useSharedQuery();

  const [form] = useForm();
  const [forgotPassword] = useForgotPasswordMutation();
  const [successfulEmail, setSuccessfulEmail] = useState<string | null>(null);

  const handleSubmit = useCallback(
    (values): void => {
      setError(null);
      (async () => {
        try {
          const email = values.email;
          await forgotPassword({
            variables: {
              email,
            },
          });
          // Success: refetch
          setSuccessfulEmail(email);
        } catch (e) {
          setError(e);
          Sentry.captureException(e);
        }
      })();
    },
    [forgotPassword, setError]
  );

  const focusElement = useRef<Input>(null);
  useEffect(
    () => void (focusElement.current && focusElement.current!.focus()),
    [focusElement]
  );

  const code = getCodeFromError(error);

  if (successfulEmail != null) {
    return (
      <SharedLayout query={query} title="Forgot Password">
        <Alert
          description={`We've sent an email reset link to '${successfulEmail}'; click the link and follow the instructions. If you don't receive the link, please ensure you entered the email address correctly, and check in your spam folder just in case.`}
          message="You've got mail"
          type="success"
        />
      </SharedLayout>
    );
  }

  return (
    <SharedLayout
      forbidWhen={AuthRestrict.LOGGED_IN}
      query={query}
      title="Forgot Password"
    >
      <Form form={form} layout="vertical" onFinish={handleSubmit}>
        <Form.Item
          name="email"
          rules={[
            {
              type: "email",
              message: "The input is not valid E-mail",
            },
            { required: true, message: "Please input your email" },
          ]}
        >
          <Input
            ref={focusElement}
            placeholder="Email"
            prefix={<UserOutlined style={{ color: "rgba(0,0,0,.25)" }} />}
          />
        </Form.Item>

        {error && (
          <Form.Item>
            <Alert
              description={
                <span>
                  {extractError(error).message}
                  {code && (
                    <span>
                      (Error code: <code>ERR_{code}</code>)
                    </span>
                  )}
                </span>
              }
              message={`Something went wrong`}
              type="error"
            />
          </Form.Item>
        )}
        <Form.Item>
          <Button htmlType="submit" type="primary">
            Reset password
          </Button>
        </Form.Item>
        <Form.Item>
          <p>
            <Link href="/login">
              <a>Remembered your password? Log in.</a>
            </Link>
          </p>
        </Form.Item>
      </Form>
    </SharedLayout>
  );
};

export default ForgotPassword;
