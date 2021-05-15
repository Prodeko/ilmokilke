import React, { useMemo } from "react";
import { Registration } from "@app/graphql";
import { Skeleton } from "antd";
import dayjs from "dayjs";
import useTranslation from "next-translate/useTranslation";

import { H4 } from "./Text";
import { SimpleTable } from ".";

interface EventRegistrationsTable {
  registrations: Registration[];
}

const getRegistrationsByQuotaPosition = (arr: any[]) => {
  return arr.reduce((a, x) => {
    const key = x?.quota?.position;
    (a[key] || (a[key] = [] || [])).push(x);
    return a;
  }, {});
};

const getQueuedRegistrations = (arr: any[]) => {
  return arr.filter((x) => x.isQueued);
};

const getQuotaNameByQuotaPosition = (arr: any[]) => {
  return arr
    .map((x) => x.quota)
    .reduce((a, x) => {
      a[x.position] = x;
      return a;
    }, {});
};

export const EventRegistrationsTable: React.FC<EventRegistrationsTable> = ({
  registrations,
}) => {
  const { t, lang } = useTranslation("events");

  const commonColumns = [
    {
      title: t("common:name"),
      dataIndex: "fullName",
      key: "fullName",
      render: (fullName: string) =>
        fullName ? (
          fullName
        ) : (
          <Skeleton.Input active={true} size="small" style={{ width: 120 }} />
        ),
    },
    {
      title: t("createdAt"),
      dataIndex: "createdAt",
      key: "createdAt",
      render: (createdAt: string) => dayjs(createdAt).format("l LT"),
    },
  ];
  const quotaColumns = [...commonColumns];
  const queuedColumns = [
    {
      title: t("quota"),
      dataIndex: ["quota", "title", lang],
      key: "quota",
    },
    ...commonColumns,
  ];

  const registrationsByQuotaPosition = useMemo(
    () => getRegistrationsByQuotaPosition(registrations),
    [registrations]
  );
  const quotaNamesByPosition = useMemo(() => getQuotaNameByQuotaPosition(registrations), [
    registrations,
  ]);
  const queuedRegistrations = useMemo(
    () => getQueuedRegistrations(registrations),
    [registrations]
  );

  return (
    <>
      {Object.keys(registrationsByQuotaPosition)
        .sort()
        .map((position) => {
          const quotaTitle = quotaNamesByPosition[position].title[lang];
          const quotaSize = quotaNamesByPosition[position].size;
          const quotaRegistrations = registrationsByQuotaPosition[position].filter(
            (r: Registration) => !r.isQueued
          );
          return (
            <div key={position}>
              <H4 style={{ marginTop: "1.5rem" }}>
                {quotaTitle} – {quotaRegistrations?.length} / {quotaSize}
              </H4>
              <SimpleTable
                columns={quotaColumns}
                data={quotaRegistrations}
                data-cy="eventpage-signups-table"
                size="small"
                style={{
                  margin: "1rem 0",
                }}
              />
            </div>
          );
        })}
      <H4 style={{ marginTop: "1.5rem" }}>{t("queued")}</H4>
      <SimpleTable
        columns={queuedColumns}
        data={queuedRegistrations}
        data-cy="eventpage-signups-table"
        size="small"
        style={{
          margin: "1rem 0",
        }}
      />
    </>
  );
};
