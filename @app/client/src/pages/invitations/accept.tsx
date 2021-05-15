import * as qs from "querystring";

import React, { useCallback, useState } from "react";
import { QueryResult } from "@apollo/client";
import {
  AuthRestrict,
  ButtonLink,
  ErrorAlert,
  Loading,
  Redirect,
  SharedLayout,
} from "@app/components";
import {
  InvitationDetailQuery,
  InvitationDetailQueryVariables,
  SharedLayout_UserFragment,
  useAcceptOrganizationInviteMutation,
  useInvitationDetailQuery,
} from "@app/graphql";
import { getCodeFromError } from "@app/lib";
import { Button, Col, Result, Row, Skeleton } from "antd";
import { NextPage } from "next";
import Router, { useRouter } from "next/router";

interface Props {
  id: string | null;
  code: string | null;
}

enum Status {
  PENDING = "PENDING",
  ACCEPTING = "ACCEPTING",
}

const InvitationAccept: NextPage<Props> = (props) => {
  const router = useRouter();
  const fullHref =
    router.pathname +
    (router && router.query ? `?${qs.stringify(router.query)}` : "");
  const { id: rawId, code } = props;
  const id = rawId || "";

  const query = useInvitationDetailQuery({
    variables: {
      id,
      code,
    },
    skip: !id,
    fetchPolicy: "network-only",
  });

  return (
    <SharedLayout
      forbidWhen={AuthRestrict.LOGGED_OUT}
      query={query}
      title="Accept Invitation"
      noHandleErrors
    >
      {({ currentUser, error, loading }) =>
        !currentUser && !error && !loading ? (
          <Redirect href={`/login?next=${encodeURIComponent(fullHref)}`} />
        ) : (
          <Row>
            <Col flex={1}>
              <InvitationAcceptInner
                code={code}
                currentUser={currentUser}
                id={id}
                query={query}
              />
            </Col>
          </Row>
        )
      }
    </SharedLayout>
  );
};

interface InvitationAcceptInnerProps extends Props {
  currentUser?: SharedLayout_UserFragment | null;
  query: QueryResult<InvitationDetailQuery, InvitationDetailQueryVariables>;
}

const InvitationAcceptInner: React.FC<InvitationAcceptInnerProps> = (props) => {
  const { id, code, query } = props;
  const router = useRouter();

  const { data, loading, error } = query;
  const [acceptInvite] = useAcceptOrganizationInviteMutation();

  const [status, setStatus] = useState(Status.PENDING);
  const [acceptError, setAcceptError] = useState<Error | null>(null);

  const organization = data?.organizationForInvitation;
  const handleAccept = useCallback(() => {
    if (!organization) {
      return;
    }
    setStatus(Status.ACCEPTING);
    // Call mutation
    acceptInvite({
      variables: {
        id,
        code,
      },
    }).then(
      () => {
        // Redirect
        Router.push(
          `/admin/organization/[slug]`,
          `/admin/organization/${organization.slug}`
        );
      },
      (e) => {
        setStatus(Status.PENDING);
        setAcceptError(e);
      }
    );
  }, [acceptInvite, code, id, organization]);

  let child: JSX.Element | null = null;
  if (status === Status.ACCEPTING) {
    child = <Loading />;
  } else if (error || acceptError) {
    const code = getCodeFromError(error || acceptError);
    if (code === "NTFND") {
      child = (
        <Result
          status="404"
          subTitle="Perhaps you have already accepted it?"
          title="That invitation could not be found"
        />
      );
    } else if (code === "DNIED") {
      child = (
        <Result
          status="403"
          subTitle="Perhaps you should log out and log in with a different account?"
          title="That invitation is not for you"
        />
      );
    } else if (code === "LOGIN") {
      child = (
        <Result
          extra={
            <ButtonLink
              href={`/login?next=${encodeURIComponent(router.asPath)}`}
            >
              Log in
            </ButtonLink>
          }
          status="403"
          title="Log in to accept invitation"
        />
      );
    } else {
      child = <ErrorAlert error={error || acceptError!} />;
    }
  } else if (organization) {
    child = (
      <Result
        extra={
          <Button type="primary" onClick={handleAccept}>
            Accept invitation
          </Button>
        }
        status="success"
        title={`You were invited to ${organization.name}`}
      />
    );
  } else if (loading) {
    child = <Skeleton />;
  } else {
    child = (
      <Result
        status="error"
        subTitle="We couldn't find details about this invite, please try again later"
        title="Something went wrong"
      />
    );
  }
  return child;
};

InvitationAccept.getInitialProps = async ({ query: { id, code } }) => ({
  id: typeof id === "string" ? id : null,
  code: typeof code === "string" ? code : null,
});

export default InvitationAccept;
