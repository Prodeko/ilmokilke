import React from "react";
import { extractError, getCodeFromError } from "@app/lib";
import { Alert } from "antd";
import useTranslation from "next-translate/useTranslation";

interface ErrorBannerProps {
  error: Error;
  setError: React.Dispatch<React.SetStateAction<Error | null>>;
}

export const ErrorBanner: React.FC<ErrorBannerProps> = ({
  error,
  setError,
  children,
}) => {
  const { t } = useTranslation("admin");
  const code = getCodeFromError(error);

  return error ? (
    <div
      style={{
        position: "fixed",
        top: "16px",
        left: "50%",
        transform: "translate(-50%, 0)",
        zIndex: 999,
      }}
    >
      <Alert
        message={
          <span>
            {t("notifications.deleteFailed")}:{" "}
            {code === "BADFK" ? <>{children}</> : extractError(error).message}{" "}
            {code && (
              <span>
                (Error code: <code>ERR_{code}</code>)
              </span>
            )}
          </span>
        }
        type="error"
        banner
        closable
        onClose={() => setError(null)}
      />
    </div>
  ) : null;
};
