import React, { useEffect } from "react";
import { useApolloClient } from "@apollo/client";
import { Skeleton } from "antd";
import Router from "next/router";
import useTranslation from "next-translate/useTranslation";

import { SharedLayout } from "./SharedLayout";
import { StandardWidth } from "./StandardWidth";
import { H3 } from "./Text";

export interface RedirectProps {
  href: string;
  as?: string;
  layout?: boolean;
}

export function Redirect({ href, as, layout }: RedirectProps) {
  const client = useApolloClient();
  const { t } = useTranslation("common");

  useEffect(() => {
    Router.push(href, as);
  }, [as, href]);

  if (layout) {
    return (
      <SharedLayout
        query={{
          loading: true,
          data: undefined,
          error: undefined,
          networkStatus: 0,
          client,
          refetch: (async () => {
            throw new Error(t("redirect"));
          }) as any,
        }}
        title={t("redirect")}
      >
        <Skeleton />
      </SharedLayout>
    );
  } else {
    return (
      <StandardWidth>
        <H3>{t("common:redirect")}</H3>
        <Skeleton />
      </StandardWidth>
    );
  }
}
