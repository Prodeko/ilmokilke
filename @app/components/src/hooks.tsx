import React, { useState } from "react";
import { QueryResult } from "@apollo/client";
import {
  EventPage_QueryFragment,
  OrganizationPage_QueryFragment,
  Registration,
  useEventRegistrationsSubscription,
} from "@app/graphql";
import { Col, Row } from "antd";
import { useRouter } from "next/router";

import { ErrorAlert, FourOhFour, LoadingPadded } from "./";

export function useQuerySlug() {
  const router = useRouter();
  const { slug: rawSlug } = router.query;
  return String(rawSlug);
}

export function useQueryId() {
  const router = useRouter();
  const { id: rawId } = router.query;
  return String(rawId);
}

export function useEventLoading(
  query: Pick<
    QueryResult<EventPage_QueryFragment>,
    "data" | "loading" | "error" | "networkStatus" | "client" | "refetch"
  >
) {
  const { data, loading, error } = query;

  let child: JSX.Element | null = null;
  const event = data?.eventBySlug;
  if (event) {
  } else if (loading) {
    child = <LoadingPadded size="huge" />;
  } else if (error) {
    child = <ErrorAlert error={error} />;
  } else {
    child = <FourOhFour currentUser={data?.currentUser} />;
  }

  return (
    child && (
      <Row>
        <Col flex={1}>{child}</Col>
      </Row>
    )
  );
}

export function useOrganizationLoading(
  query: Pick<
    QueryResult<OrganizationPage_QueryFragment>,
    "data" | "loading" | "error" | "networkStatus" | "client" | "refetch"
  >
) {
  const { data, loading, error } = query;

  let child: JSX.Element | null = null;
  const organization = data?.organizationBySlug;
  if (organization) {
  } else if (loading) {
    child = <LoadingPadded size="large" />;
  } else if (error) {
    child = <ErrorAlert error={error} />;
  } else {
    child = <FourOhFour currentUser={data?.currentUser} />;
  }

  return (
    child && (
      <Row>
        <Col flex={1}>{child}</Col>
      </Row>
    )
  );
}

export function useEventRegistrations(eventId: string, after: string, initialRegistrations: Registration[] = []) {
  const [registrations, setRegistrations] = useState<
    Registration[] | null | undefined
  >(initialRegistrations);
  useEventRegistrationsSubscription({
    variables: { eventId, after },
    skip: !eventId,
    onSubscriptionData: ({ subscriptionData }) =>
      setRegistrations(
        subscriptionData?.data?.eventRegistrations
          ?.registrations as Registration[]
      ),
  });

  return registrations
}
